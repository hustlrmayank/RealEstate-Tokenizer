;; RealEstate Tokenizer Contract
;; Tokenize real estate properties enabling fractional ownership and liquid real estate investment

;; Define the property token
(define-fungible-token property-token)

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-authorized (err u101))
(define-constant err-insufficient-balance (err u102))
(define-constant err-invalid-amount (err u103))
(define-constant err-property-not-found (err u104))
(define-constant err-property-already-exists (err u105))
(define-constant err-insufficient-payment (err u106))

;; Data Variables
(define-data-var next-property-id uint u1)

;; Property Information Structure
(define-map properties
  uint ;; property-id
  {
    owner: principal,
    property-address: (string-ascii 100),
    total-value: uint,
    total-tokens: uint,
    tokens-sold: uint,
    price-per-token: uint,
    is-active: bool
  }
)

;; Track token ownership per property per user
(define-map user-property-tokens
  {user: principal, property-id: uint}
  uint ;; number of tokens owned
)

;; Revenue distribution tracking
(define-map property-revenue
  uint ;; property-id
  uint ;; total revenue collected
)

;; Function 1: Tokenize Property
;; This function allows property owners to tokenize their real estate
(define-public (tokenize-property 
                (property-address (string-ascii 100))
                (total-value uint)
                (total-tokens uint))
  (let (
    (property-id (var-get next-property-id))
    (price-per-token (/ total-value total-tokens))
  )
    (begin
      ;; Validate inputs
      (asserts! (> total-value u0) err-invalid-amount)
      (asserts! (> total-tokens u0) err-invalid-amount)
      
      ;; Create property record
      (map-set properties property-id
        {
          owner: tx-sender,
          property-address: property-address,
          total-value: total-value,
          total-tokens: total-tokens,
          tokens-sold: u0,
          price-per-token: price-per-token,
          is-active: true
        })
      
      ;; Mint all tokens to the property owner initially
      (try! (ft-mint? property-token total-tokens tx-sender))
      
      ;; Initialize revenue tracking
      (map-set property-revenue property-id u0)
      
      ;; Set initial ownership for property owner
      (map-set user-property-tokens 
               {user: tx-sender, property-id: property-id} 
               total-tokens)
      
      ;; Increment property ID for next property
      (var-set next-property-id (+ property-id u1))
      
      (ok property-id))))

;; Function 2: Buy Property Tokens
;; This function allows investors to buy fractional ownership tokens
(define-public (buy-property-tokens 
                (property-id uint)
                (token-amount uint))
  (let (
    (property-info (unwrap! (map-get? properties property-id) err-property-not-found))
    (price-per-token (get price-per-token property-info))
    (total-cost (* token-amount price-per-token))
    (property-owner (get owner property-info))
    (current-user-tokens (default-to u0 (map-get? user-property-tokens 
                                                  {user: tx-sender, property-id: property-id})))
  )
    (begin
      ;; Validate property is active
      (asserts! (get is-active property-info) err-property-not-found)
      
      ;; Validate token amount
      (asserts! (> token-amount u0) err-invalid-amount)
      
      ;; Check if enough tokens are available
      (asserts! (<= (+ (get tokens-sold property-info) token-amount) 
                    (get total-tokens property-info)) err-insufficient-balance)
      
      ;; Transfer STX payment to property owner
      (try! (stx-transfer? total-cost tx-sender property-owner))
      
      ;; Transfer property tokens from owner to buyer
      (try! (ft-transfer? property-token token-amount property-owner tx-sender))
      
      ;; Update property tokens sold
      (map-set properties property-id
        (merge property-info {tokens-sold: (+ (get tokens-sold property-info) token-amount)}))
      
      ;; Update user's token ownership
      (map-set user-property-tokens 
               {user: tx-sender, property-id: property-id}
               (+ current-user-tokens token-amount))
      
      ;; Update property owner's token count (decrease)
      (let ((owner-current-tokens (default-to u0 (map-get? user-property-tokens 
                                                           {user: property-owner, property-id: property-id}))))
        (map-set user-property-tokens 
                 {user: property-owner, property-id: property-id}
                 (- owner-current-tokens token-amount)))
      
      (ok true))))

;; Read-only functions for querying data

;; Get property information
(define-read-only (get-property-info (property-id uint))
  (ok (map-get? properties property-id)))

;; Get user's tokens for a specific property
(define-read-only (get-user-property-tokens (user principal) (property-id uint))
  (ok (map-get? user-property-tokens {user: user, property-id: property-id})))

;; Get total number of properties
(define-read-only (get-total-properties)
  (ok (- (var-get next-property-id) u1)))

;; Get property token balance for user
(define-read-only (get-token-balance (user principal))
  (ok (ft-get-balance property-token user)))