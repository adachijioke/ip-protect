
;; title: ip-protect
;; version:
;; summary: Intellectual Property Rights Management Contract
;; description:

;; Error constants
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-IP-NOT-FOUND (err u101))
(define-constant ERR-INVALID-TRANSFER (err u102))
(define-constant ERR-LICENSING-ERROR (err u103))
(define-constant ERR-INVALID-IP-TYPE (err u105))

;; Define allowed IP types as a constant
(define-constant ALLOWED-IP-TYPES 
    (list 
        "patent" 
        "copyright" 
        "trademark" 
        "trade-secret"
        "industrial-design"
        "plant-variety"
        "geographical-indication"
    )
)

;; Data maps and storage
;; Store IP metadata
(define-map intellectual-properties
    { ip-id: uint }
    {
        creator: principal,
        ip-type: (string-ascii 50),
        registration-timestamp: uint,
        current-owner: principal,
        total-licensing-revenue: uint
    }
)

;; Store licensing details
(define-map ip-licenses
    { ip-id: uint, license-id: uint }
    {
        licensee: principal,
        license-type: (string-ascii 50),
        start-date: uint,
        end-date: uint,
        usage-rights: (list 5 (string-ascii 100)),
        royalty-rate: uint
    }
)

;; Track IP ownership history
(define-map ip-ownership-history
    { ip-id: uint }
    (list 10 principal)
)

;; Counter for IP and license IDs
(define-data-var next-ip-id uint u0)
(define-data-var next-license-id uint u0)

;; Register a new Intellectual Property
(define-public (register-ip
    (ip-type (string-ascii 23))
    (additional-metadata (optional (string-utf8 500)))
)
    
    (let 
        (
            (ip-id (+ (var-get next-ip-id) u1))
            (current-timestamp block-height)
        )
         ;; Validate IP type is in the allowed list
        (asserts! (is-some (index-of ALLOWED-IP-TYPES ip-type)) ERR-INVALID-IP-TYPE)
        ;; Increment IP ID
        (var-set next-ip-id ip-id)

        ;; Store IP metadata
        (map-set intellectual-properties 
            { ip-id: ip-id }
            {
                creator: tx-sender,
                ip-type: ip-type,
                registration-timestamp: current-timestamp,
                current-owner: tx-sender,
                total-licensing-revenue: u0
            }
        )

        ;; Update ownership history
        (map-set ip-ownership-history
            { ip-id: ip-id }
            (list tx-sender)
        )

        (ok ip-id)
    )
)

;; Issue a license for an IP
(define-public (issue-license
    (ip-id uint)
    (licensee principal)
    (license-type (string-ascii 50))
    (duration uint)
    (usage-rights (list 5 (string-ascii 100)))
    (royalty-rate uint)
)
    (let 
        (
            (current-timestamp block-height)
            (license-id (+ (var-get next-license-id) u1))
            (ip-details (unwrap! 
                (map-get? intellectual-properties { ip-id: ip-id }) 
                ERR-IP-NOT-FOUND
            ))
        )
        ;; Validate license issuance
        (asserts! (is-eq tx-sender (get current-owner ip-details)) ERR-NOT-AUTHORIZED)
        
        ;; Increment license ID
        (var-set next-license-id license-id)

        ;; Store license details
        (map-set ip-licenses
            { ip-id: ip-id, license-id: license-id }
            {
                licensee: licensee,
                license-type: license-type,
                start-date: current-timestamp,
                end-date: (+ current-timestamp duration),
                usage-rights: usage-rights,
                royalty-rate: royalty-rate
            }
        )

        (ok license-id)
    )
)

;; Transfer IP ownership
(define-public (transfer-ip-ownership
    (ip-id uint)
    (new-owner principal)
)
    (let 
        (
            (ip-details (unwrap! 
                (map-get? intellectual-properties { ip-id: ip-id }) 
                ERR-IP-NOT-FOUND
            ))
            (current-ownership-history 
                (unwrap! 
                    (map-get? ip-ownership-history { ip-id: ip-id }) 
                    (err u404)
                )
            )
        )
        ;; Validate transfer
        (asserts! (is-eq tx-sender (get current-owner ip-details)) ERR-NOT-AUTHORIZED)

        ;; Update IP ownership
        (map-set intellectual-properties 
            { ip-id: ip-id }
            (merge ip-details { current-owner: new-owner })
        )

        ;; Update ownership history
        (map-set ip-ownership-history
            { ip-id: ip-id }
            (unwrap-panic (as-max-len? 
                (append current-ownership-history new-owner) 
                u10
            ))
        )

        (ok true)
    )
)

;; Validate license usage
(define-read-only (validate-license
    (ip-id uint)
    (license-id uint)
    (intended-use (string-ascii 100))
)
    (let 
        (
            (license-details (unwrap! 
                (map-get? ip-licenses { ip-id: ip-id, license-id: license-id }) 
                ERR-IP-NOT-FOUND
            ))
            (current-timestamp block-height)
        )
        ;; Check if license is active and usage is permitted
        (ok 
            (and 
                (<= (get start-date license-details) current-timestamp)
                (>= (get end-date license-details) current-timestamp)
                (is-some (index-of (get usage-rights license-details) intended-use))
            )
        )
    )
)

;; Collect licensing revenue
(define-public (collect-licensing-revenue
    (ip-id uint)
    (amount uint)
)
    (let 
        (
            (ip-details (unwrap! 
                (map-get? intellectual-properties { ip-id: ip-id }) 
                ERR-IP-NOT-FOUND
            ))
        )
        ;; Validate revenue collection
        (asserts! (is-eq tx-sender (get current-owner ip-details)) ERR-NOT-AUTHORIZED)

        ;; Update total licensing revenue
        (map-set intellectual-properties 
            { ip-id: ip-id }
            (merge ip-details 
                { 
                    total-licensing-revenue: 
                    (+ (get total-licensing-revenue ip-details) amount) 
                }
            )
        )

        (ok true)
    )
)

;; Get IP details (read-only function)
(define-read-only (get-ip-details
    (ip-id uint)
)
    (map-get? intellectual-properties { ip-id: ip-id })
)