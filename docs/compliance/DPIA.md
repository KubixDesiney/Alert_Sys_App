# Data Protection Impact Assessment (DPIA) — SIA

A DPIA is required (GDPR Art. 35) because SIA can process **biometric data**
(voiceprint) and **location data** of employees — both high-risk. This assessment
covers those features; a customer adopting them should adopt/adapt this DPIA.

Last reviewed 2026-06-16. Decision owner: customer DPO (controller).

## 1. Description of processing
| Feature | Data | Necessity |
|---|---|---|
| Voice claim + speaker verification | Voiceprint embedding; transient audio | Hands-free claim on a noisy floor; verification prevents spoofed claims |
| Location tracking | Supervisor GPS (last-known) | Proximity-based AI assignment; locator routing to the alerting station |

## 2. Necessity & proportionality
- Both features are **opt-in at the deployment level** and tied to a specific
  operational purpose (faster, verified response). Less-intrusive alternatives
  (manual claim, manual dispatch) remain fully functional, so neither feature is
  forced — supporting proportionality.
- Data minimization: only the embedding (not raw audio) is stored for voice; only
  last-known location (not a movement history) is retained by default.

## 3. Risks & mitigations
| Risk | Likelihood × Impact | Mitigation | Residual |
|---|---|---|---|
| Biometric data breach (voiceprint) | Low × High | Stored in the customer's isolated instance; deny-by-default rules; no raw audio at rest; deletable on request | Low |
| Function creep (location used for surveillance) | Med × High | Purpose limited to assignment/routing; last-known only; controller must give worker notice; can be disabled | Low–Med |
| Lack of valid consent for biometrics | Med × High | Controller must obtain explicit consent / works-council agreement before enabling voice; documented as a precondition | Controller-owned |
| Inaccurate verification excludes a worker | Low × Med | Verification is a claim aid with manual fallback; thresholds tunable; never blocks safety response | Low |
| Cross-border transfer of PII | Low × Med | Region selection + SCCs (DPA §10) | Low |

## 4. Consultation
The controller should consult worker representatives / works council where required
(common in EU industrial settings) before enabling location or voice features.

## 5. Lawful basis
- Voiceprint (special category): **explicit consent** (Art. 9(2)(a)) is the default
  basis; the controller may rely on another Art. 9 basis where applicable.
- Location: legitimate interest with a balancing test + transparency, or consent,
  as the controller determines under local employment law.

## 6. Data subject rights
Withdrawal of consent removes the voiceprint and disables voice claim for that user;
location can be disabled per user/role; erasure honored via DSAR
(`docs/policies/data_retention_privacy_policy.md`).

## 7. Outcome
With the mitigations above — isolation, minimization, opt-in, manual fallbacks,
deletion on request, and a consent precondition for biometrics — residual risk is
assessed **acceptable** for deployment, **conditional on the controller securing the
appropriate consent/notice** for voice and location in its jurisdiction.

## 8. Review triggers
Re-run on: enabling a new biometric/location use, retaining location history,
expanding data subjects, or a change in sub-processors handling this data.
