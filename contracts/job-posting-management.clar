;; Job Posting Management Smart Contract
;; Decentralized Job Board DAO - Independent Feature
;; Clarity v3 Implementation with comprehensive error handling

;; =================================================================================
;; ERROR CONSTANTS
;; =================================================================================

(define-constant err-unauthorized (err u100))
(define-constant err-not-found (err u101))
(define-constant err-invalid-status (err u102))
(define-constant err-insufficient-funds (err u103))
(define-constant err-job-already-assigned (err u104))
(define-constant err-invalid-job-duration (err u105))
(define-constant err-job-not-assigned (err u106))
(define-constant err-invalid-freelancer (err u107))

;; =================================================================================
;; DATA VARIABLES
;; =================================================================================

(define-data-var next-job-id uint u1)
(define-data-var total-escrow-locked uint u0)

;; =================================================================================
;; DATA MAPS
;; =================================================================================

;; Job data structure
(define-map jobs
  {job-id: uint}
  {
    title: (string-utf8 100),
    description: (string-utf8 500),
    budget: uint,
    duration: uint,
    status: (string-utf8 20),
    employer: principal,
    freelancer: (optional principal),
    created-at: uint,
    assigned-at: (optional uint),
    completed-at: (optional uint)
  }
)

;; Escrow tracking for job payments
(define-map job-escrow
  {job-id: uint}
  {
    amount: uint,
    locked: bool,
    released: bool
  }
)

;; Employer reputation and statistics
(define-map employer-stats
  {employer: principal}
  {
    total-jobs-posted: uint,
    completed-jobs: uint,
    cancelled-jobs: uint,
    total-spent: uint,
    reputation-score: uint
  }
)

;; Freelancer statistics
(define-map freelancer-stats
  {freelancer: principal}
  {
    total-jobs-completed: uint,
    total-earned: uint,
    average-rating: uint,
    reputation-score: uint
  }
)

;; =================================================================================
;; PRIVATE HELPER FUNCTIONS
;; =================================================================================

(define-private (calculate-reputation-score (completed-jobs uint) (cancelled-jobs uint))
  (if (> (+ completed-jobs cancelled-jobs) u0)
    (/ (* completed-jobs u100) (+ completed-jobs cancelled-jobs))
    u0
  )
)

(define-private (is-valid-job-status (status (string-utf8 20)))
  (or 
    (is-eq status u"open")
    (or 
      (is-eq status u"in-progress")
      (or 
        (is-eq status u"completed")
        (is-eq status u"cancelled")
      )
    )
  )
)

(define-private (update-employer-reputation (employer principal) (job-completed bool))
  (let (
    (current-stats (default-to 
      {total-jobs-posted: u0, completed-jobs: u0, cancelled-jobs: u0, total-spent: u0, reputation-score: u0}
      (map-get? employer-stats {employer: employer})
    ))
  )
    (map-set employer-stats {employer: employer}
      {
        total-jobs-posted: (+ (get total-jobs-posted current-stats) u1),
        completed-jobs: (if job-completed (+ (get completed-jobs current-stats) u1) (get completed-jobs current-stats)),
        cancelled-jobs: (if (not job-completed) (+ (get cancelled-jobs current-stats) u1) (get cancelled-jobs current-stats)),
        total-spent: (get total-spent current-stats),
        reputation-score: (calculate-reputation-score 
          (if job-completed (+ (get completed-jobs current-stats) u1) (get completed-jobs current-stats))
          (if (not job-completed) (+ (get cancelled-jobs current-stats) u1) (get cancelled-jobs current-stats))
        )
      }
    )
    true
  )
)

;; =================================================================================
;; PUBLIC FUNCTIONS
;; =================================================================================

;; Create a new job posting with escrow deposit
(define-public (create-job (title (string-utf8 100)) (description (string-utf8 500)) (budget uint) (duration uint))
  (let (
    (job-id (var-get next-job-id))
    (employer tx-sender)
  )
    (asserts! (> (len title) u0) err-invalid-status)
    (asserts! (> (len description) u0) err-invalid-status)
    (asserts! (> budget u0) err-insufficient-funds)
    (asserts! (and (>= duration u1) (<= duration u365)) err-invalid-job-duration)
    
    ;; Lock funds in escrow (in a real implementation, this would transfer STX)
    (map-set job-escrow {job-id: job-id}
      {amount: budget, locked: true, released: false}
    )
    
    ;; Create job record
    (map-set jobs {job-id: job-id}
      {
        title: title,
        description: description,
        budget: budget,
        duration: duration,
        status: u"open",
        employer: employer,
        freelancer: none,
        created-at: block-height,
        assigned-at: none,
        completed-at: none
      }
    )
    
    ;; Update global counters
    (var-set next-job-id (+ job-id u1))
    (var-set total-escrow-locked (+ (var-get total-escrow-locked) budget))
    
    ;; Update employer reputation
    (update-employer-reputation employer false)
    
    (ok job-id)
  )
)

;; Assign job to a freelancer
(define-public (assign-job (job-id uint) (freelancer principal))
  (let (
    (job-data (unwrap! (map-get? jobs {job-id: job-id}) err-not-found))
  )
    (asserts! (is-eq (get employer job-data) tx-sender) err-unauthorized)
    (asserts! (is-eq (get status job-data) u"open") err-invalid-status)
    (asserts! (not (is-eq freelancer (get employer job-data))) err-invalid-freelancer)
    
    ;; Update job status and assign freelancer
    (map-set jobs {job-id: job-id}
      (merge job-data {
        status: u"in-progress",
        freelancer: (some freelancer),
        assigned-at: (some block-height)
      })
    )
    
    (ok true)
  )
)

;; Complete job and release escrow
(define-public (complete-job (job-id uint))
  (let (
    (job-data (unwrap! (map-get? jobs {job-id: job-id}) err-not-found))
    (escrow-data (unwrap! (map-get? job-escrow {job-id: job-id}) err-not-found))
  )
    (asserts! (is-eq (get employer job-data) tx-sender) err-unauthorized)
    (asserts! (is-eq (get status job-data) u"in-progress") err-invalid-status)
    (asserts! (is-some (get freelancer job-data)) err-job-not-assigned)
    
    (let (
      (freelancer-principal (unwrap-panic (get freelancer job-data)))
      (budget (get budget job-data))
    )
      ;; Update job status
      (map-set jobs {job-id: job-id}
        (merge job-data {
          status: u"completed",
          completed-at: (some block-height)
        })
      )
      
      ;; Release escrow
      (map-set job-escrow {job-id: job-id}
        (merge escrow-data {released: true, locked: false})
      )
      
      ;; Update global escrow counter
      (var-set total-escrow-locked (- (var-get total-escrow-locked) budget))
      
      ;; Update employer reputation
      (update-employer-reputation (get employer job-data) true)
      
      ;; Update freelancer stats
      (let (
        (current-freelancer-stats (default-to 
          {total-jobs-completed: u0, total-earned: u0, average-rating: u0, reputation-score: u0}
          (map-get? freelancer-stats {freelancer: freelancer-principal})
        ))
      )
        (map-set freelancer-stats {freelancer: freelancer-principal}
          {
            total-jobs-completed: (+ (get total-jobs-completed current-freelancer-stats) u1),
            total-earned: (+ (get total-earned current-freelancer-stats) budget),
            average-rating: (get average-rating current-freelancer-stats),
            reputation-score: (+ (get reputation-score current-freelancer-stats) u10)
          }
        )
      )
      
      (ok true)
    )
  )
)

;; Cancel job and refund escrow
(define-public (cancel-job (job-id uint))
  (let (
    (job-data (unwrap! (map-get? jobs {job-id: job-id}) err-not-found))
    (escrow-data (unwrap! (map-get? job-escrow {job-id: job-id}) err-not-found))
  )
    (asserts! (is-eq (get employer job-data) tx-sender) err-unauthorized)
    (asserts! (or (is-eq (get status job-data) u"open") (is-eq (get status job-data) u"in-progress")) err-invalid-status)
    
    (let (
      (budget (get budget job-data))
    )
      ;; Update job status
      (map-set jobs {job-id: job-id}
        (merge job-data {status: u"cancelled"})
      )
      
      ;; Release escrow back to employer
      (map-set job-escrow {job-id: job-id}
        (merge escrow-data {released: true, locked: false})
      )
      
      ;; Update global escrow counter
      (var-set total-escrow-locked (- (var-get total-escrow-locked) budget))
      
      ;; Update employer reputation (negatively)
      (update-employer-reputation (get employer job-data) false)
      
      (ok true)
    )
  )
)

;; =================================================================================
;; READ-ONLY FUNCTIONS
;; =================================================================================

;; Get job details by ID
(define-read-only (get-job-details (job-id uint))
  (map-get? jobs {job-id: job-id})
)

;; Get job escrow information
(define-read-only (get-job-escrow (job-id uint))
  (map-get? job-escrow {job-id: job-id})
)

;; Get employer statistics and reputation
(define-read-only (get-employer-reputation (employer principal))
  (map-get? employer-stats {employer: employer})
)

;; Get freelancer statistics and reputation
(define-read-only (get-freelancer-reputation (freelancer principal))
  (map-get? freelancer-stats {freelancer: freelancer})
)

;; Get next job ID
(define-read-only (get-next-job-id)
  (var-get next-job-id)
)

;; Get total escrow locked in system
(define-read-only (get-total-escrow-locked)
  (var-get total-escrow-locked)
)

;; Get jobs by status (limited implementation for demonstration)
(define-read-only (get-job-status (job-id uint))
  (match (map-get? jobs {job-id: job-id})
    job-data (some (get status job-data))
    none
  )
)

;; Check if job exists
(define-read-only (job-exists (job-id uint))
  (is-some (map-get? jobs {job-id: job-id}))
)
