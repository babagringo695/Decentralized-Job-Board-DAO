# 🚀 Decentralized Job Board DAO

A community-driven job board where freelancers and clients connect through blockchain transparency and DAO governance.

## 🌟 Features

### 👤 For Freelancers
- **Register** as a verified freelancer
- **Apply** to open job opportunities
- **Build reputation** through completed work
- **Get verified** through community voting
- **Receive payments** automatically via escrow

### 💼 For Clients
- **Post jobs** with automatic escrow funding
- **Review applications** from verified freelancers
- **Assign work** to qualified candidates
- **Complete payments** securely upon job completion
- **Cancel jobs** and retrieve escrowed funds

### 🏛️ DAO Governance
- **Community verification** of freelancers
- **Reputation-based voting** rights
- **Transparent rating** system
- **Automated escrow** management

## 📋 Usage

### Setup
```bash
clarinet new my-job-board
cd my-job-board
# Copy the contract to contracts/Decentralized-Job-Board-DAO.clar
clarinet check
```

### Core Functions

#### 🔧 Freelancer Operations
```clarity
;; Register as a freelancer
(contract-call? .Decentralized-Job-Board-DAO register-freelancer)

;; Apply to a job
(contract-call? .Decentralized-Job-Board-DAO apply-to-job u1)

;; Rate another freelancer (1-5 stars)
(contract-call? .Decentralized-Job-Board-DAO rate-freelancer 'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7 u5)
```

#### 💰 Client Operations
```clarity
;; Post a new job (title, description, budget, deadline)
(contract-call? .Decentralized-Job-Board-DAO post-job "Web Developer" "Build a DeFi dashboard" u1000000 u1000)

;; Assign job to freelancer
(contract-call? .Decentralized-Job-Board-DAO assign-job u1 'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7)

;; Complete job and release payment
(contract-call? .Decentralized-Job-Board-DAO complete-job u1)

;; Cancel job and get refund
(contract-call? .Decentralized-Job-Board-DAO cancel-job u1)
```

#### 🗳️ DAO Governance
```clarity
;; Propose freelancer verification
(contract-call? .Decentralized-Job-Board-DAO propose-verification 'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7)

;; Vote on verification proposal
(contract-call? .Decentralized-Job-Board-DAO vote-verification u1 true)

;; Execute verification result
(contract-call? .Decentralized-Job-Board-DAO execute-verification u1)
```

### 📖 Read-Only Functions

```clarity
;; Get job details
(contract-call? .Decentralized-Job-Board-DAO get-job u1)

;; Get freelancer profile
(contract-call? .Decentralized-Job-Board-DAO get-freelancer 'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7)

;; Get job applications
(contract-call? .Decentralized-Job-Board-DAO get-job-applications u1)

;; Get verification proposal
(contract-call? .Decentralized-Job-Board-DAO get-verification-proposal u1)
```

## 🔄 Workflow

1. **Freelancer Registration**: Users register and build reputation
2. **Job Posting**: Clients post jobs with automatic escrow
3. **Application Process**: Freelancers apply to relevant jobs
4. **Work Assignment**: Clients review and assign to best candidate
5. **Job Completion**: Automatic payment release upon completion
6. **Community Verification**: DAO members vote on freelancer verification
7. **Reputation Building**: Continuous rating and reputation system

## ⚙️ Configuration

- **Voting Period**: 144 blocks (~24 hours)
- **Min Reputation**: 50 points for proposal creation
- **Max Applications**: 20 per job
- **Reputation Gain**: 10 points per completed job

## 🧪 Testing

```bash
npm install
npm test
```

## 🚀 Deployment

```bash
clarinet deploy --network testnet
```

## 🔒 Security Features

- ✅ Automatic escrow management
- ✅ Principal-based authentication
- ✅ Reputation-gated proposals
- ✅ Time-locked voting periods
- ✅ Transparent fund tracking

## 📄 License

MIT License - Build the future of work!
