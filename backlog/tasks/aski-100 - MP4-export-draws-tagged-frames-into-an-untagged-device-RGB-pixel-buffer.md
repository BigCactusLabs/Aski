---
id: ASKI-100
title: MP4 export draws tagged frames into an untagged device-RGB pixel buffer
status: To Do
assignee: []
created_date: '2026-11-06T17:46:00Z'
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
- [ ] #1 Confirm or rule out the defect by decoding an MP4 exported from a P3 grid and from an sRGB grid with a non-neutral discriminator such as (0.8, 0.2, 0.1), and comparing decoded colors to the source
- [ ] #2 If confirmed, frames are drawn in the grid's declared space and the output carries matching color primaries, transfer function and matrix attachments (AVVideoColorPropertiesKey or pixel-buffer attachments)
- [ ] #3 GIF export and the media test phase stay green; any golden changes are re-recorded with a no-harm note; just check passes
<!-- AC:END -->
