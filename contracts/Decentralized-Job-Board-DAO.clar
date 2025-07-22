(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-already-exists (err u103))
(define-constant err-invalid-amount (err u104))
(define-constant err-job-not-open (err u105))
(define-constant err-already-applied (err u106))
(define-constant err-not-applicant (err u107))
(define-constant err-job-not-assigned (err u108))
(define-constant err-insufficient-funds (err u109))
(define-constant err-voting-ended (err u110))
(define-constant err-already-voted (err u111))

(define-data-var next-job-id uint u1)
(define-data-var next-freelancer-id uint u1)
(define-data-var next-proposal-id uint u1)
(define-data-var voting-period uint u144)
(define-data-var min-reputation uint u50)

(define-map jobs
    uint
    {
        poster: principal,
        title: (string-ascii 100),
        description: (string-ascii 500),
        budget: uint,
        status: (string-ascii 20),
        assigned-to: (optional principal),
        created-at: uint,
        deadline: uint,
    }
)

(define-map job-applications
    uint
    (list 20 principal)
)
(define-map job-escrow
    uint
    uint
)

(define-map freelancers
    principal
    {
        id: uint,
        reputation: uint,
        total-jobs: uint,
        verified: bool,
        created-at: uint,
    }
)

(define-map verification-proposals
    uint
    {
        freelancer: principal,
        proposer: principal,
        votes-for: uint,
        votes-against: uint,
        created-at: uint,
        executed: bool,
    }
)

(define-map proposal-voters
    {
        proposal-id: uint,
        voter: principal,
    }
    bool
)
(define-map freelancer-ratings
    {
        freelancer: principal,
        rater: principal,
    }
    uint
)

(define-public (register-freelancer)
    (let ((freelancer-id (var-get next-freelancer-id)))
        (asserts! (is-none (map-get? freelancers tx-sender)) err-already-exists)
        (map-set freelancers tx-sender {
            id: freelancer-id,
            reputation: u0,
            total-jobs: u0,
            verified: false,
            created-at: stacks-block-height,
        })
        (var-set next-freelancer-id (+ freelancer-id u1))
        (ok freelancer-id)
    )
)

(define-public (post-job
        (title (string-ascii 100))
        (description (string-ascii 500))
        (budget uint)
        (deadline uint)
    )
    (let ((job-id (var-get next-job-id)))
        (asserts! (> budget u0) err-invalid-amount)
        (asserts! (>= (stx-get-balance tx-sender) budget) err-insufficient-funds)
        (try! (stx-transfer? budget tx-sender (as-contract tx-sender)))
        (map-set jobs job-id {
            poster: tx-sender,
            title: title,
            description: description,
            budget: budget,
            status: "open",
            assigned-to: none,
            created-at: stacks-block-height,
            deadline: deadline,
        })
        (map-set job-escrow job-id budget)
        (var-set next-job-id (+ job-id u1))
        (ok job-id)
    )
)

(define-public (apply-to-job (job-id uint))
    (let (
            (job (unwrap! (map-get? jobs job-id) err-not-found))
            (current-applications (default-to (list) (map-get? job-applications job-id)))
        )
        (asserts! (is-some (map-get? freelancers tx-sender)) err-unauthorized)
        (asserts! (is-eq (get status job) "open") err-job-not-open)
        (asserts! (is-none (index-of current-applications tx-sender))
            err-already-applied
        )
        (map-set job-applications job-id
            (unwrap! (as-max-len? (append current-applications tx-sender) u20)
                err-not-found
            ))
        (ok true)
    )
)

(define-public (assign-job
        (job-id uint)
        (freelancer principal)
    )
    (let (
            (job (unwrap! (map-get? jobs job-id) err-not-found))
            (applications (default-to (list) (map-get? job-applications job-id)))
        )
        (asserts! (is-eq tx-sender (get poster job)) err-unauthorized)
        (asserts! (is-eq (get status job) "open") err-job-not-open)
        (asserts! (is-some (index-of applications freelancer)) err-not-applicant)
        (map-set jobs job-id
            (merge job {
                status: "assigned",
                assigned-to: (some freelancer),
            })
        )
        (ok true)
    )
)

(define-public (complete-job (job-id uint))
    (let ((job (unwrap! (map-get? jobs job-id) err-not-found)))
        (asserts! (is-eq tx-sender (get poster job)) err-unauthorized)
        (asserts! (is-eq (get status job) "assigned") err-job-not-assigned)
        (let (
                (freelancer (unwrap! (get assigned-to job) err-not-found))
                (escrow-amount (unwrap! (map-get? job-escrow job-id) err-not-found))
            )
            (try! (as-contract (stx-transfer? escrow-amount tx-sender freelancer)))
            (map-set jobs job-id (merge job { status: "completed" }))
            (map-delete job-escrow job-id)
            (try! (update-freelancer-stats freelancer))
            (ok true)
        )
    )
)

(define-public (cancel-job (job-id uint))
    (let ((job (unwrap! (map-get? jobs job-id) err-not-found)))
        (asserts! (is-eq tx-sender (get poster job)) err-unauthorized)
        (asserts!
            (or (is-eq (get status job) "open") (is-eq (get status job) "assigned"))
            err-unauthorized
        )
        (let ((escrow-amount (unwrap! (map-get? job-escrow job-id) err-not-found)))
            (try! (as-contract (stx-transfer? escrow-amount tx-sender (get poster job))))
            (map-set jobs job-id (merge job { status: "cancelled" }))
            (map-delete job-escrow job-id)
            (ok true)
        )
    )
)

(define-public (propose-verification (freelancer principal))
    (let (
            (proposal-id (var-get next-proposal-id))
            (freelancer-data (unwrap! (map-get? freelancers freelancer) err-not-found))
        )
        (asserts!
            (>=
                (get reputation
                    (unwrap! (map-get? freelancers tx-sender) err-unauthorized)
                )
                (var-get min-reputation)
            )
            err-unauthorized
        )
        (asserts! (not (get verified freelancer-data)) err-already-exists)
        (map-set verification-proposals proposal-id {
            freelancer: freelancer,
            proposer: tx-sender,
            votes-for: u0,
            votes-against: u0,
            created-at: stacks-block-height,
            executed: false,
        })
        (var-set next-proposal-id (+ proposal-id u1))
        (ok proposal-id)
    )
)

(define-public (vote-verification
        (proposal-id uint)
        (vote bool)
    )
    (let (
            (proposal (unwrap! (map-get? verification-proposals proposal-id) err-not-found))
            (voter-key {
                proposal-id: proposal-id,
                voter: tx-sender,
            })
        )
        (asserts! (is-some (map-get? freelancers tx-sender)) err-unauthorized)
        (asserts!
            (< (+ (get created-at proposal) (var-get voting-period))
                stacks-block-height
            )
            err-voting-ended
        )
        (asserts! (is-none (map-get? proposal-voters voter-key))
            err-already-voted
        )
        (map-set proposal-voters voter-key true)
        (if vote
            (map-set verification-proposals proposal-id
                (merge proposal { votes-for: (+ (get votes-for proposal) u1) })
            )
            (map-set verification-proposals proposal-id
                (merge proposal { votes-against: (+ (get votes-against proposal) u1) })
            )
        )
        (ok true)
    )
)

(define-public (execute-verification (proposal-id uint))
    (let ((proposal (unwrap! (map-get? verification-proposals proposal-id) err-not-found)))
        (asserts!
            (>= (+ (get created-at proposal) (var-get voting-period))
                stacks-block-height
            )
            err-voting-ended
        )
        (asserts! (not (get executed proposal)) err-already-exists)
        (map-set verification-proposals proposal-id
            (merge proposal { executed: true })
        )
        (if (> (get votes-for proposal) (get votes-against proposal))
            (begin
                (map-set freelancers (get freelancer proposal)
                    (merge
                        (unwrap! (map-get? freelancers (get freelancer proposal))
                            err-not-found
                        ) { verified: true }
                    ))
                (ok true)
            )
            (ok false)
        )
    )
)

(define-public (rate-freelancer
        (freelancer principal)
        (rating uint)
    )
    (begin
        (asserts! (and (>= rating u1) (<= rating u5)) err-invalid-amount)
        (asserts! (is-some (map-get? freelancers freelancer)) err-not-found)
        (map-set freelancer-ratings {
            freelancer: freelancer,
            rater: tx-sender,
        }
            rating
        )
        (ok true)
    )
)

(define-private (update-freelancer-stats (freelancer principal))
    (let ((freelancer-data (unwrap! (map-get? freelancers freelancer) err-not-found)))
        (map-set freelancers freelancer
            (merge freelancer-data {
                total-jobs: (+ (get total-jobs freelancer-data) u1),
                reputation: (+ (get reputation freelancer-data) u10),
            })
        )
        (ok true)
    )
)

(define-read-only (get-job (job-id uint))
    (map-get? jobs job-id)
)

(define-read-only (get-freelancer (address principal))
    (map-get? freelancers address)
)

(define-read-only (get-job-applications (job-id uint))
    (default-to (list) (map-get? job-applications job-id))
)

(define-read-only (get-verification-proposal (proposal-id uint))
    (map-get? verification-proposals proposal-id)
)

(define-read-only (get-freelancer-rating
        (freelancer principal)
        (rater principal)
    )
    (map-get? freelancer-ratings {
        freelancer: freelancer,
        rater: rater,
    })
)

(define-read-only (get-contract-balance)
    (stx-get-balance (as-contract tx-sender))
)

(define-read-only (get-next-job-id)
    (var-get next-job-id)
)

(define-read-only (get-next-freelancer-id)
    (var-get next-freelancer-id)
)

(define-read-only (get-voting-period)
    (var-get voting-period)
)

(define-read-only (get-min-reputation)
    (var-get min-reputation)
)
