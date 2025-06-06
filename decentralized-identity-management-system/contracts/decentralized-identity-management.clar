
;; title: decentralized-identity-management
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-UNAUTHORIZED (err u1))
(define-constant ERR-INVALID-IDENTITY (err u2))
(define-constant ERR-ATTRIBUTE-UPDATE-FAILED (err u3))
(define-constant ERR-SERVICE-ACCESS-DENIED (err u4))
(define-constant ERR-IDENTITY-EXISTS (err u5))



;; Identity Struct
(define-map Identities 
  principal 
  {
    did: (buff 32),                ;; Decentralized Identifier
    attributes-hash: (buff 32),    ;; Encrypted attributes hash
    created-at: uint,              ;; Creation timestamp
    updated-at: uint,              ;; Last update timestamp
    is-active: bool                ;; Identity status
  }
)

;; Service Access Permissions
(define-map ServiceAccess 
  {
    identity: principal, 
    service-did: principal
  }
  {
    allowed-attributes: (list 10 (string-ascii 50)),
    expiration: uint
  }
)

;; Attribute Verification Requests
(define-map VerificationRequests
  {
    requester: principal,
    identity: principal
  }
  {
    requested-attributes: (list 10 (string-ascii 50)),
    status: (string-ascii 20),
    created-at: uint
  }
)

;; Create New Identity
(define-public (create-identity 
  (did (buff 32))
  (attributes-hash (buff 32))
)
  (if (is-none (map-get? Identities tx-sender))
    (let 
      (
        (current-timestamp u0)  ;; Simulated timestamp (replace with a real mechanism if needed)
      )
      (map-set Identities 
        tx-sender 
        {
          did: did,
          attributes-hash: attributes-hash,
          created-at: current-timestamp,
          updated-at: current-timestamp,
          is-active: true
        }
      )
      
      (ok true)
    )
    (err ERR-IDENTITY-EXISTS)  ;; Error if identity already exists
  )
)

;; Signature verification function
(define-private (is-valid-signature 
  (signature (buff 64)) 
  (did (buff 32))
) 
  ;; Placeholder signature validation
  (is-eq signature did)
)

;; Update Identity Attributes
(define-public (update-attributes
  (new-attributes-hash (buff 32))
  (signature (buff 64))
)
  (match (map-get? Identities tx-sender)
    current-identity
      (begin
        ;; Verify signature and authorization
        (if 
          (and 
            (is-eq (get is-active current-identity) true)
            (is-valid-signature signature (get did current-identity))
          )
          ;; If verification passes, update attributes
          (begin
            (map-set Identities 
              tx-sender 
              (merge current-identity {
                attributes-hash: new-attributes-hash,
                updated-at: u0  ;; Use a placeholder for current timestamp
              })
            )
            (ok true)
          )
          ;; If verification fails, return unauthorized error
          (err ERR-UNAUTHORIZED)
        )
      )
    ;; If no identity found, return invalid identity error
    (err ERR-INVALID-IDENTITY)
  )
)

;; Request Service Access
(define-public (request-service-access
  (service-did principal)
  (requested-attributes (list 10 (string-ascii 50)))
)
  (match (map-get? Identities tx-sender)
    current-identity
      (begin
        ;; Create verification request
        (map-set VerificationRequests
          {
            requester: service-did,
            identity: tx-sender
          }
          {
            requested-attributes: requested-attributes,
            status: "PENDING",
            created-at: u0  ;; Use a placeholder timestamp
          }
        )
        
        (ok true)
      )
    ;; If no identity found, return invalid identity error
    (err ERR-INVALID-IDENTITY)
  )
)

;; Approve Service Access
(define-public (approve-service-access
  (service-did principal)
  (allowed-attributes (list 10 (string-ascii 50)))
  (expiration uint)
)
  (let 
    (
      ;; Attempt to get the verification request
      (verification-request 
        (map-get? VerificationRequests 
          {
            requester: service-did,
            identity: tx-sender
          }
        )
      )
    )
    ;; Check if verification request exists
    (match verification-request
      request
        (begin
          ;; Verify the request is still pending
          (if (not (is-eq (get status request) "PENDING"))
            (err u2)  ;; Direct error code instead of unresolved constant
            (begin
              ;; Store service access permissions
              (map-set ServiceAccess
                {
                  identity: tx-sender,
                  service-did: service-did
                }
                {
                  allowed-attributes: allowed-attributes,
                  expiration: expiration
                }
              )
              
              ;; Update verification request status
              (map-set VerificationRequests
                {
                  requester: service-did,
                  identity: tx-sender
                }
                {
                  requested-attributes: allowed-attributes,
                  status: "APPROVED",
                  created-at: (get created-at request)
                }
              )
              
              (ok true)
            )
          )
        )
      ;; If no verification request found, return error
      (err u1)  ;; Direct error code
    )
  )
)

(define-public (revoke-service-access
  (service-did principal)
)
  (let 
    (
      (access-entry 
        (map-get? ServiceAccess 
          {
            identity: tx-sender,
            service-did: service-did
          }
        )
      )
    )
    (match access-entry
      entry
        (begin
          ;; Remove service access
          (map-delete ServiceAccess 
            {
              identity: tx-sender,
              service-did: service-did
            }
          )
          
          ;; Update verification request status
          (map-set VerificationRequests
            {
              requester: service-did,
              identity: tx-sender
            }
            {
              requested-attributes: (get allowed-attributes entry),
              status: "REVOKED",
              created-at: u0
            }
          )
          
          (ok true)
        )
      (err ERR-SERVICE-ACCESS-DENIED)
    )
  )
)

(define-map IdentityReputation
  principal
  {
    trust-score: uint,
    total-verifications: uint,
    successful-verifications: uint
  }
)

;; Update Reputation After Verification
(define-private (update-reputation
  (identity principal)
  (is-successful bool)
)
  (match (map-get? IdentityReputation identity)
    current-reputation
      (let 
        (
          (new-total (+ (get total-verifications current-reputation) u1))
          (new-successful 
            (if is-successful 
              (+ (get successful-verifications current-reputation) u1)
              (get successful-verifications current-reputation)
            )
          )
          (new-trust-score 
            (/ 
              (* (get successful-verifications current-reputation) u100) 
              new-total
            )
          )
        )
        (map-set IdentityReputation 
          identity 
          {
            trust-score: new-trust-score,
            total-verifications: new-total,
            successful-verifications: new-successful
          }
        )
      )
    ;; Initialize reputation if not exists
    (map-set IdentityReputation 
      identity 
      {
        trust-score: (if is-successful u100 u0),
        total-verifications: u1,
        successful-verifications: (if is-successful u1 u0)
      }
    )
  )
)

(define-map RecoveryGuardians
  principal
  (list 3 principal)
)

(define-public (add-recovery-guardians
  (guardians (list 3 principal))
)
  (begin
    (map-set RecoveryGuardians 
      tx-sender 
      guardians
    )
    (ok true)
  )
)

(define-public (verify-identity-for-contract
  (contract-address principal)
  (required-attributes (list 10 (string-ascii 50)))
)
  (match (map-get? Identities tx-sender)
    identity
      (let 
        (
          (has-service-access 
            (is-some 
              (map-get? ServiceAccess 
                {
                  identity: tx-sender,
                  service-did: contract-address
                }
              )
            )
          )
        )
        (if has-service-access
          (ok true)
          (err ERR-SERVICE-ACCESS-DENIED)
        )
      )
    (err ERR-INVALID-IDENTITY)
  )
)