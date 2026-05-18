<div align="center">

<!-- HERO BANNER -->
<img width="100%" src="https://capsule-render.vercel.app/api?type=waving&color=0:0D4A75,50:1a6fa8,100:60A5FA&height=200&section=header&text=Smart Industrial Alert - SIA&fontSize=72&fontColor=ffffff&fontAlignY=40&desc=Industrial%20Intelligence%2C%20Redefined&descAlignY=65&descSize=22&animation=fadeIn" />

<br/>

<h1>
  <img src="https://readme-typing-svg.demolab.com?font=Inter&weight=700&size=32&pause=1000&color=60A5FA&center=true&vCenter=true&width=600&lines=Factory+Floor+Alert+Intelligence;Voice-First+Industrial+Control;AI-Powered+Predictive+Ops;Real-Time+Supervisor+Dispatch" alt="Typing SVG" />
</h1>

<br/>

<!-- BADGES ROW 1 -->
<p>
  <img src="https://img.shields.io/badge/Flutter-3.x-02569B?style=for-the-badge&logo=flutter&logoColor=white" />
  <img src="https://img.shields.io/badge/Dart-3.x-0175C2?style=for-the-badge&logo=dart&logoColor=white" />
  <img src="https://img.shields.io/badge/Firebase-Realtime_DB-FFCA28?style=for-the-badge&logo=firebase&logoColor=black" />
  <img src="https://img.shields.io/badge/Cloudflare-Workers-F48120?style=for-the-badge&logo=cloudflare&logoColor=white" />
  <img src="https://img.shields.io/badge/TensorFlow_Lite-ML_Models-FF6F00?style=for-the-badge&logo=tensorflow&logoColor=white" />
</p>

<!-- BADGES ROW 2 -->
<p>
  <img src="https://img.shields.io/badge/Platform-Android_|_iOS_|_Windows_|_Linux_|_Web-6366F1?style=for-the-badge" />
  <img src="https://img.shields.io/badge/AI-Claude_+_Gemini_Powered-8B5CF6?style=for-the-badge&logo=anthropic&logoColor=white" />
  <img src="https://img.shields.io/badge/Shorebird-Code_Push_Enabled-10B981?style=for-the-badge" />
</p>

<!-- BADGES ROW 3 -->
<p>
  <img src="https://img.shields.io/badge/Voice-Offline_Sherpa_ONNX-EF4444?style=for-the-badge" />
  <img src="https://img.shields.io/badge/Station_Scan-QR_History_Lookup-0EA5E9?style=for-the-badge" />
  <img src="https://img.shields.io/badge/License-Proprietary-1E293B?style=for-the-badge" />
</p>

<br/>

> **Smart Industrial Alert - SIA** is an enterprise-grade, AI-driven factory alert management platform built for real industrial environments.
> Voice-first, offline-capable, and engineered to operate in the loudest, most demanding factory floors on earth.

<br/>

---

</div>

## Table of Contents

- [Overview](#-overview)
- [Core Features](#-core-features)
- [Voice Intelligence](#-voice-intelligence)
- [AI & Machine Learning](#-ai--machine-learning)
- [Architecture](#-architecture)
- [Technology Stack](#-technology-stack)
- [Screens & UI](#-screens--ui)
- [Platform Support](#-platform-support)
- [Backend Infrastructure](#-backend-infrastructure)
- [Getting Started](#-getting-started)
- [Configuration](#-configuration)
- [Project Structure](#-project-structure)

---

## Overview

<table>
<tr>
<td width="60%">

Smart Industrial Alert - SIA is a **full-stack industrial supervision platform** designed from the ground up for high-noise, high-stakes manufacturing environments. It replaces fragmented radio systems and paper-based workflows with a unified, intelligent layer that routes alerts, verifies identities through voice biometrics, predicts failures before they happen, and provides hands-free control to supervisors â€” all running offline on the factory floor.

**Built for factories. Engineered for scale. Designed for zero downtime.**

</td>
<td width="40%" align="center">

```
ðŸ­  Factory Operations Layer
       â†•  Real-time sync
ðŸ”¥  Firebase + Cloudflare Edge
       â†•  AI pipeline
ðŸ¤–  TFLite + Claude + ONNX
       â†•  Voice interface
ðŸŽ¤  Offline ASR + Speaker ID
       â†•  Mobile/Desktop
ðŸ“±  Flutter Multi-Platform App
```

</td>
</tr>
</table>

---

## Core Features

<div align="center">

### Alert Lifecycle Management

</div>

| Feature | Description |
|---|---|
| **Multi-Type Alerts** | Quality (`qualite`), Maintenance, Product Defects (`defaut_produit`), Resource Deficiency (`manque_ressource`) |
| **Human-Readable IDs** | Every alert gets a numeric ID starting at `1000` â€” speakable by voice ("Alert one zero two five") |
| **Full Status Lifecycle** | `open â†’ claimed â†’ in_progress â†’ resolved / escalated` with timestamped transitions |
| **Critical Flag System** | Mark alerts critical with custom notes and type-specific escalation thresholds |
| **Comments & Resolution Notes** | Structured resolution comments attached to every alert for audit trails |
| **Auto-Escalation** | Cloudflare Worker cron triggers automatic escalation of unclaimed alerts after configurable timeout |

<div align="center">

### Collaboration & Escalation

</div>

| Feature | Description |
|---|---|
| **Multi-Supervisor Collaboration** | Request help from peers with message context and approval/refuse workflows |
| **Admin Escalation Dashboard** | Dedicated view for Production Managers to escalate and audit critical alerts |
| **Escalation Reasoning** | Every escalation carries notes, a reason, and full audit history |
| **AI Assignment** | Automatic supervisor matching with full scoring breakdown and "why not others" reasoning |

<div align="center">

### Factory Hierarchy & Location Intelligence

</div>

```
Usine (Factory)
 â””â”€â”€ Conveyor Line
       â””â”€â”€ Workstation
             â””â”€â”€ Machine Asset (with full history)
```

- Alerts are always bound to a valid node in the hierarchy
- Asset management with machine IDs and asset history
- Location-aware AI assignment â€” closer supervisors score higher
- QR codes at each station let supervisors identify a workstation and load its alert history instantly

---

## Voice Intelligence

<div align="center">

```
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚                   VOICE PIPELINE                        â”‚
â”‚                                                         â”‚
â”‚  ðŸŽ¤ Native Android AudioRecord (16kHz PCM mono)         â”‚
â”‚         â†“ RMS silence detection (900ms threshold)       â”‚
â”‚  ðŸ“¦ Sherpa ONNX Streaming Zipformer (~17MB int8)        â”‚
â”‚         â†“ 30% lower WER than alternatives in noise      â”‚
â”‚  ðŸ§  TFLite Speaker Embedding (conformer_tisid_small)    â”‚
â”‚         â†“ Cosine similarity â‰¥ 0.80 to authenticate      â”‚
â”‚  ðŸ” VoiceCommandParser (num-word â†’ digit + intent)      â”‚
â”‚         â†“ claim / resolve / escalate / navigate         â”‚
â”‚  âš¡ VoiceCommandDispatcher â†’ AlertProvider action        â”‚
â”‚         â†“                                               â”‚
â”‚  ðŸ”Š flutter_tts confirmation (max vol + focus steal)    â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
```

</div>

### Voice Commands

| Utterance | Action |
|---|---|
| `"Claim alert one zero two five"` | Claims alert #1025 for the authenticated speaker |
| `"Resolve alert one zero two five"` | Marks alert #1025 as resolved |
| `"Escalate alert one zero two five"` | Escalates alert #1025 to admin |
| `"Show dashboard"` | Navigates to main dashboard |
| `"Show alerts"` | Opens alert list |

### Speaker Verification

- **TFLite conformer model** generates speaker embeddings from raw audio
- **Cosine similarity threshold**: `0.80` â€” tuned for factory-grade accuracy
- **Quality gates**: minimum 600ms of speech, SNR â‰¥ 6 dB
- **VAD trimming**: silence stripped from both ends before embedding
- **Enrollment UI**: guided multi-sample enrollment flow for new supervisors

### Lock Screen Voice Actions

- Full-screen `VoiceLockRecorderActivity` launches above Android keyguard
- FCM notification carries `voice_claim` action button â€” tap opens voice claim screen on the lock screen
- Post-notification flow: **record â†’ transcribe â†’ verify identity â†’ execute â†’ speak confirmation**
- `fullScreenIntent` with `boostMediaVolume()` ensures TTS cuts through factory noise

### Offline-First STT

- **Primary**: Sherpa ONNX streaming Zipformer â€” fully offline after one-time model download
- **Fallback**: `speech_to_text` plugin for non-Android platforms
- Zero dependency on cloud connectivity on the factory floor
- Model stored in app data directory, compressed archive on first launch

---

## AI & Machine Learning

<div align="center">

```
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚                      AI INTELLIGENCE LAYER                         â”‚
â”‚                                                                    â”‚
â”‚  â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚  â”‚  AI ASSIGNMENT      â”‚   â”‚  PREDICTIVE INTELLIGENCE         â”‚   â”‚
â”‚  â”‚                     â”‚   â”‚                                  â”‚   â”‚
â”‚  â”‚  Scoring Model:     â”‚   â”‚  â€¢ Morning briefing (daily)      â”‚   â”‚
â”‚  â”‚  â€¢ Workload weight  â”‚   â”‚  â€¢ Failure risk curves           â”‚   â”‚
â”‚  â”‚  â€¢ Expertise match  â”‚   â”‚  â€¢ Hourly probability dist.      â”‚   â”‚
â”‚  â”‚  â€¢ Location prox.   â”‚   â”‚  â€¢ Per-factory risk scores       â”‚   â”‚
â”‚  â”‚  â€¢ Success rate     â”‚   â”‚  â€¢ Assignee predictions          â”‚   â”‚
â”‚  â”‚                     â”‚   â”‚                                  â”‚   â”‚
â”‚  â”‚  Confidence: 0-100  â”‚   â”‚  Powered by historical alert     â”‚   â”‚
â”‚  â”‚  Cooldown: 5 min    â”‚   â”‚  patterns + factory metadata     â”‚   â”‚
â”‚  â”‚  Debounce: 1.5s     â”‚   â”‚                                  â”‚   â”‚
â”‚  â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                                                    â”‚
â”‚  â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚  â”‚  AI RESOLUTION      â”‚   â”‚  VOICE BIOMETRICS                â”‚   â”‚
â”‚  â”‚  SUGGESTIONS        â”‚   â”‚                                  â”‚   â”‚
â”‚  â”‚                     â”‚   â”‚  TFLite Speaker Embedding        â”‚   â”‚
â”‚  â”‚  Claude API via     â”‚   â”‚  â€¢ 16kHz mono PCM input          â”‚   â”‚
â”‚  â”‚  Cloudflare Worker  â”‚   â”‚  â€¢ conformer_tisid_small.tflite  â”‚   â”‚
â”‚  â”‚                     â”‚   â”‚  â€¢ Cosine sim >= 0.80            â”‚   â”‚
â”‚  â”‚  Context: type,     â”‚   â”‚  â€¢ VAD + SNR quality gates       â”‚   â”‚
â”‚  â”‚  location, history  â”‚   â”‚  â€¢ Multi-enrollment averaging    â”‚   â”‚
â”‚  â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
```

</div>

### AI Assignment Engine

The rule-based scoring model evaluates every available supervisor against a weighted multi-criteria function:

```
score = w1Â·(1/workload) + w2Â·expertise_match + w3Â·location_proximity + w4Â·recent_success_rate
```

- **Decision transparency**: every assignment includes full per-supervisor score breakdown
- **Rejection feedback**: supervisors can reject assignments; feedback feeds back into the scoring model
- **Deduplication**: 5-minute factory lock with 1.5s debounce prevents duplicate assignments
- **AI Logs Panel**: admin view of every AI decision with full reasoning trace

### Predictive Intelligence

- **Morning Briefing**: AI-generated daily summary of overnight alerts, resolution stats, and risk hotspots
- **Failure Prediction**: probability curves per factory line for upcoming 8-hour shift
- **Risk Heatmaps**: visual overlay on factory layout with ML-derived risk coloring
- **Predictive Cards**: dashboard widgets surfacing imminent-failure signals to supervisors before alerts fire

### Claude-Powered Resolution Suggestions

- Cloudflare Worker proxies requests to the Claude API
- Prompt includes: alert type, workstation location, machine asset history, past resolutions for similar alerts
- Response rendered inline in the alert detail screen
- Graceful offline fallback when edge worker is unreachable

---

## Architecture

```
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚                            Smart Industrial Alert - SIA ARCHITECTURE                             â”‚
â”‚                                                                              â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”  â”‚
â”‚   â”‚   FLUTTER    â”‚   â”‚   FIREBASE   â”‚   â”‚  CLOUDFLARE  â”‚   â”‚  SHOREBIRD â”‚  â”‚
â”‚   â”‚   APP        â”‚   â”‚              â”‚   â”‚  WORKERS     â”‚   â”‚  CODE PUSH â”‚  â”‚
â”‚   â”‚              â”‚<â”€â”€â”¤ Realtime DB  â”‚   â”‚              â”‚   â”‚            â”‚  â”‚
â”‚   â”‚ Provider     â”‚   â”‚ Firestore    â”‚<â”€â”€â”¤ Cron AI      â”‚   â”‚ OTA deploy â”‚  â”‚
â”‚   â”‚ Screens      â”‚<â”€â”€â”¤ Cloud Funcs  â”‚   â”‚ Escalation   â”‚   â”‚ Zero-down  â”‚  â”‚
â”‚   â”‚ Services     â”‚   â”‚ Auth         â”‚   â”‚ Push fan-out â”‚   â”‚ time patch â”‚  â”‚
â”‚   â”‚ Models       â”‚<â”€â”€â”¤ FCM          â”‚   â”‚ JWT signing  â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜  â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”¬â”€â”€â”€â”€â”€â”€â”€â”˜   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜                   â”‚
â”‚          â”‚                                                                   â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â–¼â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚                     PLATFORM CHANNELS (Android)                     â”‚   â”‚
â”‚   â”‚  VoiceLockRecorderActivity  Â·  boostMediaVolume()  Â·  Keyguard API  â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                                                              â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”  â”‚
â”‚   â”‚                        ON-DEVICE ML STACK                            â”‚  â”‚
â”‚   â”‚   Sherpa ONNX (offline ASR)  Â·  TFLite (speaker embedding)           â”‚  â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜  â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
```

### State Management

- **Provider** pattern with `AlertProvider` as the central state atom
- Streams from Firebase Realtime Database, composed with **RxDart** operators
- Platform-specific service resolution via conditional Dart imports (`_stub.dart` / `_io.dart`)
- Background FCM handler registered with `@pragma('vm:entry-point')` for foreground & killed-app delivery

### Data Flow

```
Firebase RTDB stream
  â†’ AlertProvider (Provider)
    â†’ UI rebuilds (Consumer widgets)
      â†’ User action (tap / voice command)
        â†’ AlertProvider method
          â†’ Firebase write
            â†’ Cloudflare Worker triggered (if needed)
              â†’ FCM push to all supervisors
```

---

## Technology Stack

<div align="center">

| Layer | Technology | Purpose |
|---|---|---|
| **UI Framework** | Flutter 3.x + Dart 3.x | Cross-platform app |
| **State** | Provider 6.x + RxDart | Reactive state management |
| **Backend DB** | Firebase Realtime Database | Live alert streams |
| **Secondary DB** | Cloud Firestore | Structured data, AI logs |
| **Auth** | Firebase Authentication | Role-based access |
| **Push** | Firebase Cloud Messaging | Real-time notifications |
| **Edge Compute** | Cloudflare Workers | AI scoring, escalation cron |
| **Offline ASR** | Sherpa ONNX (Zipformer int8) | Factory-floor speech-to-text |
| **Voice Biometrics** | TFLite (conformer_tisid) | Speaker identity verification |
| **AI Suggestions** | Claude API (via CF Worker) | Resolution recommendations |
| **Predictive AI** | Google Generative AI | Morning briefings, risk curves |
| **Station Scan** | mobile_scanner | QR workstation lookup and alert history |
| **Notifications** | flutter_local_notifications | Full-screen lock-screen alerts |
| **Code Push** | Shorebird | Zero-downtime OTA updates |
| **TTS** | flutter_tts | Factory-loud voice feedback |
| **Typography** | Google Fonts (Inter) | Consistent UI typography |
| **Exports** | csv + excel + printing | Alert report generation |

</div>

---

## Screens & UI

<div align="center">

### 24+ Screens across the full supervisor journey

</div>

```
Authentication
  â”œâ”€â”€ Login Screen
  â””â”€â”€ Role Gate (Admin / Supervisor / Production Manager)

Dashboard (Overview)
  â”œâ”€â”€ Health Score Gauge
  â”œâ”€â”€ Critical Alerts Card
  â”œâ”€â”€ Predictive Failure Card
  â”œâ”€â”€ AI Morning Briefing Hero
  â””â”€â”€ Insights Strip

Alert Management
  â”œâ”€â”€ Alerts Tree (hierarchical, heatmap-colored)
  â”œâ”€â”€ Alert Detail (comments, resolution, AI suggestion)
  â”œâ”€â”€ Alert Scan Screen (mobile / web variants)
  â””â”€â”€ Escalated Alerts (admin view)

Voice Features
  â”œâ”€â”€ Voice Claim Screen (lock-screen capable)
  â”œâ”€â”€ Voice Enrollment Screen (guided multi-sample)
  â””â”€â”€ Push-to-Talk overlay

Supervision
  â”œâ”€â”€ Supervisor Tab (availability, workload)
  â”œâ”€â”€ Collaboration Screen (help requests, accept/refuse)
  â””â”€â”€ Admin Escalation Dashboard

Factory Management
  â”œâ”€â”€ Factory Mapping Tab (custom layout)
  â”œâ”€â”€ Alert Locator (custom painter map)
  â””â”€â”€ Asset Management

Intelligence
  â”œâ”€â”€ AI Logs Panel (assignment decision trace)
  â”œâ”€â”€ Predictive Heatmaps
  â””â”€â”€ Morning Briefing View
```

### Theme System

Smart Industrial Alert - SIA ships with a polished **dual-mode design system**:

| Token | Light Mode | Dark Mode |
|---|---|---|
| Background | `#F8FAFC` | `#0F172A` |
| Card Surface | `#FFFFFF` | `#1E293B` |
| Primary Brand | `#0D4A75` (navy) | `#60A5FA` (blue) |
| Critical | `#EF4444` | `#EF4444` |
| Success | `#10B981` | `#10B981` |
| Warning | `#F59E0B` | `#F59E0B` |
| Escalation | `#8B5CF6` | `#8B5CF6` |

- Material Design 3 `ColorScheme` integration
- `context.appTheme.navy`, `context.isDark` extension helpers
- Custom card theming, navigation bar theming, and input decoration
- Inter font family throughout

---

## Platform Support

| Platform | Status | Voice | Station Scan | Offline ASR |
|---|:---:|:---:|:---:|:---:|
| Android | Full | Native | Yes | Yes |
| iOS | Supported | Fallback | Yes | Partial |
| Windows | Supported | Fallback | â€” | Partial |
| Linux | Supported | Fallback | â€” | Partial |
| macOS | Supported | Fallback | Yes | Partial |
| Web | Supported | Fallback | Manual entry | â€” |

> **Android is the primary deployment target.** Native `VoiceLockRecorderActivity` and full offline Sherpa ONNX pipeline are Android-only. Other platforms use `speech_to_text` plugin fallback.

---

## Backend Infrastructure

### Firebase Architecture

```
firebase/
  â”œâ”€â”€ Realtime Database   â†’ Live alert streams, supervisor state
  â”œâ”€â”€ Firestore           â†’ AI decision logs, structured metadata
  â”œâ”€â”€ Cloud Functions     â†’ Assignment cooldowns, factory locks (15s TTL)
  â”œâ”€â”€ Cloud Messaging     â†’ Push to supervisors, voice_claim actions
  â””â”€â”€ Authentication      â†’ UID-based role gates
```

### Cloudflare Workers

**Primary Worker** (`cloudflare_worker.js` â€” 49 KB):

| Cron Trigger | Action |
|---|---|
| Every minute | AI scoring run â€” matches unassigned alerts to supervisors |
| Every minute | Escalation check â€” auto-escalates stale unclaimed alerts |
| Every minute | Push fan-out â€” broadcasts qualifying alerts to available supervisors |

- Custom Firebase JWT generation (service account signing, no Admin SDK required at edge)
- Rate-limited: max 1 alert/push, 5 escalation checks, 20 factories per cron run
- Supervisor availability scoring at the edge layer

**Secondary Worker** (`WORKER_UPDATE_FILTER_CLAIMED.js`):
- Claimed-filter real-time synchronization for UX snappiness

### Firebase Cloud Functions

- AI assignment cooldown enforcement
- Factory-level lock acquisition with 15-second TTL (prevents race conditions)
- Supervisor availability tracking
- Alert deduplication and processor matching

---

## Getting Started

### Prerequisites

```bash
# Flutter SDK (3.x recommended)
flutter --version

# Firebase CLI
npm install -g firebase-tools
firebase login

# Android SDK (API 21+)
# NDK required for Sherpa ONNX native libs
```

### Installation

```bash
# 1. Clone the repository
git clone https://github.com/your-org/Smart Industrial Alert - SIAapp.git
cd Smart Industrial Alert - SIAapp

# 2. Install Flutter dependencies
flutter pub get

# 3. Configure environment
cp .env.example .env
# Fill in your Firebase project credentials and Cloudflare Worker URL

# 4. Configure Firebase
flutterfire configure --project=YOUR_FIREBASE_PROJECT_ID

# 5. Run on Android (recommended)
flutter run --release
```

### First Launch

1. **Voice Enrollment**: Supervisors record 3â€“5 samples to build their voice profile
2. **Model Download**: Sherpa ONNX ASR model (~17 MB) downloads once, then fully offline
3. **FCM Token**: Device registers for push notifications automatically
4. **Role Assignment**: Admin assigns supervisor/manager roles via Firebase console

---

## Configuration

### Environment Variables (`.env`)

```env
CLOUDFLARE_WORKER_URL=https://your-worker.your-subdomain.workers.dev
FIREBASE_API_KEY=...
FIREBASE_APP_ID=...
FIREBASE_MESSAGING_SENDER_ID=...
FIREBASE_PROJECT_ID=...
FIREBASE_STORAGE_BUCKET=...
FIREBASE_DATABASE_URL=...
```

### Escalation Thresholds (Cloudflare Worker)

```javascript
// cloudflare_worker.js
const ESCALATION_THRESHOLDS = {
  qualite:           10 * 60 * 1000,  // 10 minutes
  maintenance:       15 * 60 * 1000,  // 15 minutes
  defaut_produit:     5 * 60 * 1000,  //  5 minutes
  manque_ressource:  10 * 60 * 1000,  // 10 minutes
};
```

### AI Assignment Weights

```dart
// lib/services/ai_assignment_service.dart
const double workloadWeight    = 0.35;
const double expertiseWeight   = 0.30;
const double locationWeight    = 0.20;
const double successRateWeight = 0.15;
```

### Voice Auth Sensitivity

```dart
// lib/services/voice_auth_service_io.dart
const double similarityThreshold = 0.80;   // cosine similarity
const double minSNRdB            = 6.0;    // minimum signal quality
const int    minSpeechMs         = 600;    // minimum speech duration (ms)
```

---

## Project Structure

```
Smart Industrial Alert - SIAapp/
â”‚
â”œâ”€â”€ lib/
â”‚   â”œâ”€â”€ main.dart                          # App entry, Firebase init, auth gate
â”‚   â”œâ”€â”€ theme.dart                         # AppTheme light/dark + context extensions
â”‚   â”‚
â”‚   â”œâ”€â”€ models/                            # Data models
â”‚   â”‚   â”œâ”€â”€ alert_model.dart
â”‚   â”‚   â”œâ”€â”€ user_model.dart
â”‚   â”‚   â”œâ”€â”€ collaboration_model.dart
â”‚   â”‚   â””â”€â”€ hierarchy_model.dart
â”‚   â”‚
â”‚   â”œâ”€â”€ providers/                         # State management
â”‚   â”‚   â””â”€â”€ alert_provider.dart            # Central alert + supervisor state
â”‚   â”‚
â”‚   â”œâ”€â”€ services/                          # 30+ service classes
â”‚   â”‚   â”œâ”€â”€ alert_service.dart
â”‚   â”‚   â”œâ”€â”€ ai_service.dart                # Claude API proxy
â”‚   â”‚   â”œâ”€â”€ ai_assignment_service.dart     # Scoring + auto-assignment
â”‚   â”‚   â”œâ”€â”€ predictive_intel_service.dart  # Morning briefings, risk curves
â”‚   â”‚   â”œâ”€â”€ voice_service.dart             # Platform-conditional entry
â”‚   â”‚   â”œâ”€â”€ voice_service_io.dart          # Android native impl
â”‚   â”‚   â”œâ”€â”€ voice_service_stub.dart        # Non-Android stub
â”‚   â”‚   â”œâ”€â”€ voice_auth_service_io.dart     # TFLite speaker verification
â”‚   â”‚   â”œâ”€â”€ sherpa_stt_service_io.dart     # Offline ASR
â”‚   â”‚   â”œâ”€â”€ voice_command_parser.dart      # Intent + number parsing
â”‚   â”‚   â”œâ”€â”€ voice_command_dispatcher.dart  # Command â†’ AlertProvider bridge
â”‚   â”‚   â”œâ”€â”€ fcm_service.dart
â”‚   â”‚   â”œâ”€â”€ offline_db_service.dart
â”‚   â”‚   â””â”€â”€ ...
â”‚   â”‚
â”‚   â”œâ”€â”€ screens/                           # 24+ screens
â”‚   â”‚   â”œâ”€â”€ dashboard_screen.dart
â”‚   â”‚   â”œâ”€â”€ alerts_tree_screen.dart
â”‚   â”‚   â”œâ”€â”€ voice_claim_screen.dart
â”‚   â”‚   â”œâ”€â”€ voice_enrollment_screen.dart
â”‚   â”‚   â”œâ”€â”€ alert_scan_screen.dart
â”‚   â”‚   â”œâ”€â”€ admin_escalation_screen.dart
â”‚   â”‚   â”œâ”€â”€ collaboration_screen.dart
â”‚   â”‚   â””â”€â”€ ...
â”‚   â”‚
â”‚   â””â”€â”€ widgets/                           # Reusable components
â”‚       â”œâ”€â”€ voice_command_button.dart
â”‚       â”œâ”€â”€ ai_logs_panel.dart
â”‚       â”œâ”€â”€ predictive_heatmap_widget.dart
â”‚       â””â”€â”€ ...
â”‚
â”œâ”€â”€ android/
â”‚   â””â”€â”€ app/src/main/kotlin/com/example/Smart Industrial Alert - SIAapp/
â”‚       â”œâ”€â”€ MainActivity.kt
â”‚       â””â”€â”€ VoiceLockRecorderActivity.kt   # Native audio + keyguard bypass
â”‚
â”œâ”€â”€ assets/
â”‚   â””â”€â”€ models/
â”‚       â””â”€â”€ conformer_tisid_small.tflite   # Speaker embedding model
â”‚
â”œâ”€â”€ functions/                             # Firebase Cloud Functions (Node.js)
â”‚   â””â”€â”€ index.js
â”‚
â”œâ”€â”€ cloudflare_worker.js                   # Edge AI scoring + escalation cron
â”œâ”€â”€ WORKER_UPDATE_FILTER_CLAIMED.js        # Claimed filter sync worker
â”œâ”€â”€ pubspec.yaml                           # Flutter dependencies
â”œâ”€â”€ firebase.json                          # Firebase config
â””â”€â”€ shorebird.yaml                         # Code push configuration
```

---

<div align="center">

## Built With Conviction

```
"Factory floors don't wait.
 Neither should your alerts."
```

<br/>

<p>
  <img src="https://img.shields.io/badge/Made_with-Flutter-02569B?style=flat-square&logo=flutter" />
  <img src="https://img.shields.io/badge/Powered_by-Firebase-FFCA28?style=flat-square&logo=firebase&logoColor=black" />
  <img src="https://img.shields.io/badge/AI_by-Claude_+_Gemini-8B5CF6?style=flat-square" />
  <img src="https://img.shields.io/badge/Edge_by-Cloudflare-F48120?style=flat-square&logo=cloudflare&logoColor=white" />
</p>

<img width="100%" src="https://capsule-render.vercel.app/api?type=waving&color=0:60A5FA,50:1a6fa8,100:0D4A75&height=120&section=footer&animation=fadeIn" />

</div>

