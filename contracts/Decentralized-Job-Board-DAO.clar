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
(define-constant err-milestone-not-found (err u112))
(define-constant err-milestone-completed (err u113))
(define-constant err-milestone-not-completed (err u114))
(define-constant err-dispute-exists (err u115))
(define-constant err-dispute-not-found (err u116))
(define-constant err-dispute-resolved (err u117))
(define-constant err-invalid-dispute-type (err u118))
(define-constant err-dispute-voting-active (err u119))
(define-constant err-no-dispute-rights (err u120))

(define-data-var next-job-id uint u1)
(define-data-var next-milestone-id uint u1)
(define-data-var next-freelancer-id uint u1)
(define-data-var next-proposal-id uint u1)
(define-data-var voting-period uint u144)
(define-data-var min-reputation uint u50)
(define-data-var next-dispute-id uint u1)
(define-data-var dispute-voting-period uint u288)

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

(define-map job-milestones
    uint
    {
        job-id: uint,
        description: (string-ascii 200),
        payment-amount: uint,
        completed: bool,
        approved: bool,
        freelancer-submitted: bool,
        created-at: uint,
    }
)

(define-map job-milestone-ids
    uint
    (list 10 uint)
)

(define-map job-disputes
    uint
    {
        job-id: uint,
        initiator: principal,
        dispute-type: (string-ascii 20),
        description: (string-ascii 300),
        evidence-hash: (optional (string-ascii 64)),
        status: (string-ascii 20),
        votes-for-client: uint,
        votes-for-freelancer: uint,
        created-at: uint,
        resolved-at: (optional uint),
        resolution: (optional (string-ascii 20)),
    }
)

(define-map dispute-voters
    {
        dispute-id: uint,
        voter: principal,
    }
    (string-ascii 20)
)

(define-map job-dispute-id
    uint
    (optional uint)
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

(define-public (create-milestone
        (job-id uint)
        (description (string-ascii 200))
        (payment-amount uint)
    )
    (let (
            (job (unwrap! (map-get? jobs job-id) err-not-found))
            (milestone-id (var-get next-milestone-id))
            (current-milestones (default-to (list) (map-get? job-milestone-ids job-id)))
        )
        (asserts! (is-eq tx-sender (get poster job)) err-unauthorized)
        (asserts! (> payment-amount u0) err-invalid-amount)
        (asserts! (< (len current-milestones) u10) err-already-exists)
        (map-set job-milestones milestone-id {
            job-id: job-id,
            description: description,
            payment-amount: payment-amount,
            completed: false,
            approved: false,
            freelancer-submitted: false,
            created-at: stacks-block-height,
        })
        (map-set job-milestone-ids job-id
            (unwrap! (as-max-len? (append current-milestones milestone-id) u10)
                err-not-found
            ))
        (var-set next-milestone-id (+ milestone-id u1))
        (ok milestone-id)
    )
)

(define-public (submit-milestone (milestone-id uint))
    (let (
            (milestone (unwrap! (map-get? job-milestones milestone-id)
                err-milestone-not-found
            ))
            (job (unwrap! (map-get? jobs (get job-id milestone)) err-not-found))
        )
        (asserts!
            (is-eq tx-sender (unwrap! (get assigned-to job) err-unauthorized))
            err-unauthorized
        )
        (asserts! (not (get completed milestone)) err-milestone-completed)
        (map-set job-milestones milestone-id
            (merge milestone { freelancer-submitted: true })
        )
        (ok true)
    )
)

(define-public (approve-milestone (milestone-id uint))
    (let (
            (milestone (unwrap! (map-get? job-milestones milestone-id)
                err-milestone-not-found
            ))
            (job (unwrap! (map-get? jobs (get job-id milestone)) err-not-found))
        )
        (asserts! (is-eq tx-sender (get poster job)) err-unauthorized)
        (asserts! (get freelancer-submitted milestone)
            err-milestone-not-completed
        )
        (asserts! (not (get approved milestone)) err-milestone-completed)
        (let (
                (payment-amount (get payment-amount milestone))
                (freelancer (unwrap! (get assigned-to job) err-unauthorized))
                (escrow-amount (unwrap! (map-get? job-escrow (get job-id milestone))
                    err-not-found
                ))
            )
            (asserts! (>= escrow-amount payment-amount) err-insufficient-funds)
            (try! (as-contract (stx-transfer? payment-amount tx-sender freelancer)))
            (map-set job-escrow (get job-id milestone)
                (- escrow-amount payment-amount)
            )
            (map-set job-milestones milestone-id
                (merge milestone {
                    completed: true,
                    approved: true,
                })
            )
            (ok true)
        )
    )
)

(define-read-only (get-milestone (milestone-id uint))
    (map-get? job-milestones milestone-id)
)

(define-read-only (get-job-milestones (job-id uint))
    (default-to (list) (map-get? job-milestone-ids job-id))
)

(define-read-only (get-next-milestone-id)
    (var-get next-milestone-id)
)

(define-public (create-dispute
        (job-id uint)
        (dispute-type (string-ascii 20))
        (description (string-ascii 300))
        (evidence-hash (optional (string-ascii 64)))
    )
    (let (
            (job (unwrap! (map-get? jobs job-id) err-not-found))
            (dispute-id (var-get next-dispute-id))
            (existing-dispute (map-get? job-dispute-id job-id))
        )
        (asserts! (is-none (unwrap-panic existing-dispute)) err-dispute-exists)
        (asserts!
            (or
                (is-eq tx-sender (get poster job))
                (is-eq tx-sender (unwrap! (get assigned-to job) err-unauthorized))
            )
            err-no-dispute-rights
        )
        (asserts!
            (or
                (is-eq dispute-type "payment")
                (is-eq dispute-type "quality")
                (is-eq dispute-type "deadline")
                (is-eq dispute-type "scope")
            )
            err-invalid-dispute-type
        )
        (asserts! (is-eq (get status job) "assigned") err-job-not-assigned)
        (map-set job-disputes dispute-id {
            job-id: job-id,
            initiator: tx-sender,
            dispute-type: dispute-type,
            description: description,
            evidence-hash: evidence-hash,
            status: "active",
            votes-for-client: u0,
            votes-for-freelancer: u0,
            created-at: stacks-block-height,
            resolved-at: none,
            resolution: none,
        })
        (map-set job-dispute-id job-id (some dispute-id))
        (var-set next-dispute-id (+ dispute-id u1))
        (ok dispute-id)
    )
)

(define-public (vote-dispute
        (dispute-id uint)
        (vote-for (string-ascii 20))
    )
    (let (
            (dispute (unwrap! (map-get? job-disputes dispute-id) err-dispute-not-found))
            (voter-key {
                dispute-id: dispute-id,
                voter: tx-sender,
            })
            (voter-data (unwrap! (map-get? freelancers tx-sender) err-unauthorized))
        )
        (asserts! (is-eq (get status dispute) "active") err-dispute-resolved)
        (asserts!
            (<= (+ (get created-at dispute) (var-get dispute-voting-period))
                stacks-block-height
            )
            err-voting-ended
        )
        (asserts! (get verified voter-data) err-unauthorized)
        (asserts! (is-none (map-get? dispute-voters voter-key)) err-already-voted)
        (asserts! (or (is-eq vote-for "client") (is-eq vote-for "freelancer"))
            err-invalid-amount
        )
        (map-set dispute-voters voter-key vote-for)
        (if (is-eq vote-for "client")
            (map-set job-disputes dispute-id
                (merge dispute { votes-for-client: (+ (get votes-for-client dispute) u1) })
            )
            (map-set job-disputes dispute-id
                (merge dispute { votes-for-freelancer: (+ (get votes-for-freelancer dispute) u1) })
            )
        )
        (ok true)
    )
)

(define-public (resolve-dispute (dispute-id uint))
    (let (
            (dispute (unwrap! (map-get? job-disputes dispute-id) err-dispute-not-found))
            (job (unwrap! (map-get? jobs (get job-id dispute)) err-not-found))
            (escrow-amount (unwrap! (map-get? job-escrow (get job-id dispute)) err-not-found))
        )
        (asserts! (is-eq (get status dispute) "active") err-dispute-resolved)
        (asserts!
            (> (+ (get created-at dispute) (var-get dispute-voting-period))
                stacks-block-height
            )
            err-dispute-voting-active
        )
        (let (
                (client-votes (get votes-for-client dispute))
                (freelancer-votes (get votes-for-freelancer dispute))
                (winner (if (> client-votes freelancer-votes)
                    "client"
                    "freelancer"
                ))
                (freelancer (unwrap! (get assigned-to job) err-not-found))
            )
            (map-set job-disputes dispute-id
                (merge dispute {
                    status: "resolved",
                    resolved-at: (some stacks-block-height),
                    resolution: (some winner),
                })
            )
            (if (is-eq winner "client")
                (begin
                    (try! (as-contract (stx-transfer? escrow-amount tx-sender (get poster job))))
                    (map-set jobs (get job-id dispute)
                        (merge job { status: "cancelled" })
                    )
                )
                (begin
                    (try! (as-contract (stx-transfer? escrow-amount tx-sender freelancer)))
                    (map-set jobs (get job-id dispute)
                        (merge job { status: "completed" })
                    )
                    (try! (update-freelancer-stats freelancer))
                )
            )
            (map-delete job-escrow (get job-id dispute))
            (map-delete job-dispute-id (get job-id dispute))
            (ok winner)
        )
    )
)

(define-read-only (get-dispute (dispute-id uint))
    (map-get? job-disputes dispute-id)
)

(define-read-only (get-job-dispute (job-id uint))
    (match (map-get? job-dispute-id job-id)
        dispute-id (map-get? job-disputes (unwrap-panic dispute-id))
        none
    )
)

(define-read-only (get-dispute-vote
        (dispute-id uint)
        (voter principal)
    )
    (map-get? dispute-voters {
        dispute-id: dispute-id,
        voter: voter,
    })
)

(define-read-only (get-next-dispute-id)
    (var-get next-dispute-id)
)

(define-read-only (get-dispute-voting-period)
    (var-get dispute-voting-period)
)
