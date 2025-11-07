;; GridLeap - Dynamic Trading Card Game Ecosystem
;; A revolutionary blockchain gaming platform with evolving NFT cards

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-token-owner (err u101))
(define-constant err-card-not-found (err u102))
(define-constant err-insufficient-balance (err u103))
(define-constant err-already-staked (err u104))
(define-constant err-not-staked (err u105))
(define-constant err-fusion-cooldown (err u106))
(define-constant err-invalid-fusion (err u107))
(define-constant err-already-voted (err u108))
(define-constant err-proposal-not-found (err u109))
(define-constant err-proposal-expired (err u110))

;; Data Variables
(define-data-var card-id-nonce uint u0)
(define-data-var proposal-id-nonce uint u0)
(define-data-var platform-fee-percentage uint u250) ;; 2.5% in basis points

;; Data Maps

;; Card NFT Storage
(define-map cards
    uint
    {
        owner: principal,
        card-type: (string-ascii 50),
        rarity: (string-ascii 20),
        power-level: uint,
        evolution-stage: uint,
        last-evolution: uint,
        wins: uint,
        losses: uint,
        created-at: uint
    }
)

;; Card Evolution Data
(define-map card-evolution-data
    uint
    {
        oracle-feed-value: uint,
        performance-multiplier: uint,
        evolution-points: uint
    }
)

;; Staking Information
(define-map staked-cards
    uint
    {
        staker: principal,
        staked-at: uint,
        rewards-accumulated: uint
    }
)

;; Card Fusion Tracking
(define-map fusion-cooldowns
    principal
    uint ;; block-height when cooldown expires
)

;; Governance Proposals
(define-map proposals
    uint
    {
        proposer: principal,
        title: (string-utf8 256),
        description: (string-utf8 1024),
        votes-for: uint,
        votes-against: uint,
        end-block: uint,
        executed: bool
    }
)

;; Voting Records
(define-map votes
    {proposal-id: uint, voter: principal}
    {vote-weight: uint, vote-for: bool}
)

;; Marketplace Listings
(define-map card-listings
    uint
    {
        seller: principal,
        price: uint,
        listed-at: uint
    }
)

;; Rental System
(define-map card-rentals
    uint
    {
        owner: principal,
        renter: principal,
        rental-price: uint,
        rental-end: uint
    }
)

;; Token Balances (LEAP tokens)
(define-map leap-balances
    principal
    uint
)

;; Read-only functions

(define-read-only (get-card (card-id uint))
    (map-get? cards card-id)
)

(define-read-only (get-card-evolution-data (card-id uint))
    (map-get? card-evolution-data card-id)
)

(define-read-only (get-staked-card-info (card-id uint))
    (map-get? staked-cards card-id)
)

(define-read-only (get-leap-balance (account principal))
    (default-to u0 (map-get? leap-balances account))
)

(define-read-only (get-proposal (proposal-id uint))
    (map-get? proposals proposal-id)
)

(define-read-only (get-card-listing (card-id uint))
    (map-get? card-listings card-id)
)

(define-read-only (get-card-rental (card-id uint))
    (map-get? card-rentals card-id)
)

(define-read-only (get-platform-fee)
    (var-get platform-fee-percentage)
)

(define-read-only (get-fusion-cooldown (account principal))
    (default-to u0 (map-get? fusion-cooldowns account))
)

(define-read-only (calculate-staking-rewards (card-id uint))
    (let
        (
            (stake-info (unwrap! (map-get? staked-cards card-id) u0))
            (card-info (unwrap! (map-get? cards card-id) u0))
            (blocks-staked (- block-height (get staked-at stake-info)))
            (power-multiplier (get power-level card-info))
        )
        (+ (get rewards-accumulated stake-info)
           (* blocks-staked power-multiplier))
    )
)

;; Private functions

(define-private (mint-leap-tokens (recipient principal) (amount uint))
    (let
        (
            (current-balance (get-leap-balance recipient))
        )
        (map-set leap-balances recipient (+ current-balance amount))
        true
    )
)

(define-private (burn-leap-tokens (account principal) (amount uint))
    (let
        (
            (current-balance (get-leap-balance account))
        )
        (asserts! (>= current-balance amount) err-insufficient-balance)
        (map-set leap-balances account (- current-balance amount))
        (ok true)
    )
)

(define-private (transfer-leap-tokens (sender principal) (recipient principal) (amount uint))
    (begin
        (try! (burn-leap-tokens sender amount))
        (mint-leap-tokens recipient amount)
        (ok true)
    )
)

;; Public functions

;; Mint a new card
(define-public (mint-card (card-type (string-ascii 50)) (rarity (string-ascii 20)) (initial-power uint))
    (let
        (
            (new-card-id (+ (var-get card-id-nonce) u1))
        )
        (map-set cards new-card-id
            {
                owner: tx-sender,
                card-type: card-type,
                rarity: rarity,
                power-level: initial-power,
                evolution-stage: u1,
                last-evolution: block-height,
                wins: u0,
                losses: u0,
                created-at: block-height
            }
        )
        (map-set card-evolution-data new-card-id
            {
                oracle-feed-value: u100,
                performance-multiplier: u100,
                evolution-points: u0
            }
        )
        (var-set card-id-nonce new-card-id)
        (ok new-card-id)
    )
)

;; Transfer card ownership
(define-public (transfer-card (card-id uint) (recipient principal))
    (let
        (
            (card-info (unwrap! (map-get? cards card-id) err-card-not-found))
        )
        (asserts! (is-eq (get owner card-info) tx-sender) err-not-token-owner)
        (map-set cards card-id (merge card-info {owner: recipient}))
        (ok true)
    )
)

;; Record battle result and award LEAP tokens
(define-public (record-battle-result (card-id uint) (won bool))
    (let
        (
            (card-info (unwrap! (map-get? cards card-id) err-card-not-found))
            (evolution-data (unwrap! (map-get? card-evolution-data card-id) err-card-not-found))
            (reward-amount (if won u100 u25))
        )
        (asserts! (is-eq (get owner card-info) tx-sender) err-not-token-owner)
        (map-set cards card-id
            (merge card-info
                {
                    wins: (if won (+ (get wins card-info) u1) (get wins card-info)),
                    losses: (if won (get losses card-info) (+ (get losses card-info) u1))
                }
            )
        )
        (map-set card-evolution-data card-id
            (merge evolution-data
                {evolution-points: (+ (get evolution-points evolution-data) (if won u10 u2))}
            )
        )
        (mint-leap-tokens tx-sender reward-amount)
        (ok true)
    )
)

;; Evolve card using evolution points
(define-public (evolve-card (card-id uint))
    (let
        (
            (card-info (unwrap! (map-get? cards card-id) err-card-not-found))
            (evolution-data (unwrap! (map-get? card-evolution-data card-id) err-card-not-found))
            (evolution-cost (* (get evolution-stage card-info) u100))
        )
        (asserts! (is-eq (get owner card-info) tx-sender) err-not-token-owner)
        (asserts! (>= (get evolution-points evolution-data) evolution-cost) err-insufficient-balance)
        (map-set cards card-id
            (merge card-info
                {
                    evolution-stage: (+ (get evolution-stage card-info) u1),
                    power-level: (+ (get power-level card-info) u50),
                    last-evolution: block-height
                }
            )
        )
        (map-set card-evolution-data card-id
            (merge evolution-data
                {evolution-points: (- (get evolution-points evolution-data) evolution-cost)}
            )
        )
        (ok true)
    )
)

;; Update oracle feed value (contract owner only)
(define-public (update-oracle-feed (card-id uint) (new-value uint))
    (let
        (
            (evolution-data (unwrap! (map-get? card-evolution-data card-id) err-card-not-found))
        )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (map-set card-evolution-data card-id
            (merge evolution-data {oracle-feed-value: new-value})
        )
        (ok true)
    )
)

;; Stake card for passive rewards
(define-public (stake-card (card-id uint))
    (let
        (
            (card-info (unwrap! (map-get? cards card-id) err-card-not-found))
        )
        (asserts! (is-eq (get owner card-info) tx-sender) err-not-token-owner)
        (asserts! (is-none (map-get? staked-cards card-id)) err-already-staked)
        (map-set staked-cards card-id
            {
                staker: tx-sender,
                staked-at: block-height,
                rewards-accumulated: u0
            }
        )
        (ok true)
    )
)

;; Unstake card and claim rewards
(define-public (unstake-card (card-id uint))
    (let
        (
            (stake-info (unwrap! (map-get? staked-cards card-id) err-not-staked))
            (total-rewards (calculate-staking-rewards card-id))
        )
        (asserts! (is-eq (get staker stake-info) tx-sender) err-not-token-owner)
        (mint-leap-tokens tx-sender total-rewards)
        (map-delete staked-cards card-id)
        (ok total-rewards)
    )
)

;; Fuse two cards to create a new one
(define-public (fuse-cards (card-id-1 uint) (card-id-2 uint))
    (let
        (
            (card-1 (unwrap! (map-get? cards card-id-1) err-card-not-found))
            (card-2 (unwrap! (map-get? cards card-id-2) err-card-not-found))
            (cooldown-end (get-fusion-cooldown tx-sender))
            (new-card-id (+ (var-get card-id-nonce) u1))
            (combined-power (+ (get power-level card-1) (get power-level card-2)))
        )
        (asserts! (is-eq (get owner card-1) tx-sender) err-not-token-owner)
        (asserts! (is-eq (get owner card-2) tx-sender) err-not-token-owner)
        (asserts! (< cooldown-end block-height) err-fusion-cooldown)
        (map-delete cards card-id-1)
        (map-delete cards card-id-2)
        (map-delete card-evolution-data card-id-1)
        (map-delete card-evolution-data card-id-2)
        (map-set cards new-card-id
            {
                owner: tx-sender,
                card-type: "Fused",
                rarity: (get rarity card-1),
                power-level: combined-power,
                evolution-stage: u1,
                last-evolution: block-height,
                wins: u0,
                losses: u0,
                created-at: block-height
            }
        )
        (map-set card-evolution-data new-card-id
            {
                oracle-feed-value: u100,
                performance-multiplier: u110,
                evolution-points: u0
            }
        )
        (map-set fusion-cooldowns tx-sender (+ block-height u144)) ;; ~24 hour cooldown
        (var-set card-id-nonce new-card-id)
        (ok new-card-id)
    )
)

;; List card on marketplace
(define-public (list-card (card-id uint) (price uint))
    (let
        (
            (card-info (unwrap! (map-get? cards card-id) err-card-not-found))
        )
        (asserts! (is-eq (get owner card-info) tx-sender) err-not-token-owner)
        (map-set card-listings card-id
            {
                seller: tx-sender,
                price: price,
                listed-at: block-height
            }
        )
        (ok true)
    )
)

;; Purchase card from marketplace
(define-public (purchase-card (card-id uint))
    (let
        (
            (listing (unwrap! (map-get? card-listings card-id) err-card-not-found))
            (card-info (unwrap! (map-get? cards card-id) err-card-not-found))
            (price (get price listing))
            (seller (get seller listing))
            (platform-fee (/ (* price (var-get platform-fee-percentage)) u10000))
            (seller-amount (- price platform-fee))
        )
        (try! (transfer-leap-tokens tx-sender seller seller-amount))
        (try! (transfer-leap-tokens tx-sender contract-owner platform-fee))
        (map-set cards card-id (merge card-info {owner: tx-sender}))
        (map-delete card-listings card-id)
        (ok true)
    )
)

;; Create governance proposal
(define-public (create-proposal (title (string-utf8 256)) (description (string-utf8 1024)) (voting-period uint))
    (let
        (
            (new-proposal-id (+ (var-get proposal-id-nonce) u1))
        )
        (map-set proposals new-proposal-id
            {
                proposer: tx-sender,
                title: title,
                description: description,
                votes-for: u0,
                votes-against: u0,
                end-block: (+ block-height voting-period),
                executed: false
            }
        )
        (var-set proposal-id-nonce new-proposal-id)
        (ok new-proposal-id)
    )
)

;; Vote on proposal (weighted voting with LEAP tokens)
(define-public (vote-on-proposal (proposal-id uint) (vote-for bool) (token-amount uint))
    (let
        (
            (proposal (unwrap! (map-get? proposals proposal-id) err-proposal-not-found))
            (voter-balance (get-leap-balance tx-sender))
            (vote-weight token-amount)
        )
        (asserts! (>= voter-balance token-amount) err-insufficient-balance)
        (asserts! (< block-height (get end-block proposal)) err-proposal-expired)
        (asserts! (is-none (map-get? votes {proposal-id: proposal-id, voter: tx-sender})) err-already-voted)
        (map-set votes {proposal-id: proposal-id, voter: tx-sender}
            {vote-weight: vote-weight, vote-for: vote-for}
        )
        (map-set proposals proposal-id
            (merge proposal
                {
                    votes-for: (if vote-for (+ (get votes-for proposal) vote-weight) (get votes-for proposal)),
                    votes-against: (if vote-for (get votes-against proposal) (+ (get votes-against proposal) vote-weight))
                }
            )
        )
        (try! (burn-leap-tokens tx-sender token-amount))
        (ok true)
    )
)

;; Rent card to another player
(define-public (rent-out-card (card-id uint) (rental-price uint) (rental-duration uint))
    (let
        (
            (card-info (unwrap! (map-get? cards card-id) err-card-not-found))
        )
        (asserts! (is-eq (get owner card-info) tx-sender) err-not-token-owner)
        (map-set card-rentals card-id
            {
                owner: tx-sender,
                renter: tx-sender,
                rental-price: rental-price,
                rental-end: (+ block-height rental-duration)
            }
        )
        (ok true)
    )
)

;; Rent a card
(define-public (rent-card (card-id uint))
    (let
        (
            (rental-info (unwrap! (map-get? card-rentals card-id) err-card-not-found))
            (rental-price (get rental-price rental-info))
            (owner (get owner rental-info))
        )
        (try! (transfer-leap-tokens tx-sender owner rental-price))
        (map-set card-rentals card-id
            (merge rental-info {renter: tx-sender})
        )
        (ok true)
    )
)

;; Update platform fee (contract owner only)
(define-public (set-platform-fee (new-fee uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set platform-fee-percentage new-fee)
        (ok true)
    )
)

