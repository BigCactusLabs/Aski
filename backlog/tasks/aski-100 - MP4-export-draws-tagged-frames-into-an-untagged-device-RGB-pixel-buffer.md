---
id: ASKI-100
title: MP4 export draws tagged frames into an untagged device-RGB pixel buffer
status: To Do
assignee: []
created_date: '2026-11-06T17:46:00Z'
updated_date: '2026-11-10T02:17:00Z'
labels:
  - correctness
  - video
  - color
dependencies: []
references:
  - Sources/Aski/Video/ASCIIVideoEncoder.swift
priority: medium
type: bug
ordinal: 101000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in the ASKI-3 review; not yet reproduced. `ASCIIVideoEncoder` (Sources/Aski/Video/ASCIIVideoEncoder.swift, around lines 160-173) draws sRGB- or Display P3-tagged rendered frames into a `CVPixelBuffer` through a DeviceRGB context and attaches no color properties (primaries, transfer function, YCbCr matrix) to the buffer or the writer. Players may then interpret P3 frames as sRGB or Rec. 709, and the drawing step may color-match unpredictably. Apple's TN2313 says DeviceRGB treatment varies by framework.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Confirm or rule out the defect by decoding an MP4 exported from a P3 grid and from an sRGB grid with a non-neutral discriminator such as (0.8, 0.2, 0.1), and comparing decoded colors to the source
- [ ] #2 If confirmed, frames are drawn in the grid's declared space and the output carries matching color primaries, transfer function and matrix attachments (AVVideoColorPropertiesKey or pixel-buffer attachments)
- [ ] #3 GIF export and the media test phase stay green; any golden changes are re-recorded with a no-harm note; just check passes
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Phase 1 (2026-11-09, macOS 27): CONFIRMED. Track carries no ColorPrimaries/TransferFunction/YCbCrMatrix extensions (H.264 and HEVC). VideoToolbox encodes with the BT.709 matrix; AVAssetReader guesses for untagged tracks by size (SMPTE-C + BT.601 at <=384 px tall, BT.709 at >=768 px), so small sRGB exports decode (204,51,26) -> (189,37,29). DeviceRGB draw acts as sRGB on this host: a P3 frame (204,51,26) becomes clipped sRGB (222,24,0) before encoding, so P3 gamut is lost. Gray control round-trips. Characterization: Tests/AskiTests/AskiVideoColorTaggingTests.swift (withKnownIssue for tags + small-frame round trip; two current-behavior pins to rewrite in the fix).
<!-- SECTION:NOTES:END -->
