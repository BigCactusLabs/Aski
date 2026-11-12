---
id: ASKI-100
title: MP4 export draws tagged frames into an untagged device-RGB pixel buffer
status: Done
assignee: []
created_date: '2026-11-06T17:46:00Z'
updated_date: '2026-11-10T06:18:00Z'
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
- [x] #2 If confirmed, frames are drawn in the grid's declared space and the output carries matching color primaries, transfer function and matrix attachments (AVVideoColorPropertiesKey or pixel-buffer attachments)
- [x] #3 GIF export and the media test phase stay green; any golden changes are re-recorded with a no-harm note; just check passes
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Phase 1 (2026-11-09, macOS 27): CONFIRMED. Track carries no ColorPrimaries/TransferFunction/YCbCrMatrix extensions (H.264 and HEVC). VideoToolbox encodes with the BT.709 matrix; AVAssetReader guesses for untagged tracks by size (SMPTE-C + BT.601 at <=384 px tall, BT.709 at >=768 px), so small sRGB exports decode (204,51,26) -> (189,37,29). DeviceRGB draw acts as sRGB on this host: a P3 frame (204,51,26) becomes clipped sRGB (222,24,0) before encoding, so P3 gamut is lost. Gray control round-trips. Characterization: Tests/AskiTests/AskiVideoColorTaggingTests.swift (withKnownIssue for tags + small-frame round trip; two current-behavior pins to rewrite in the fix).

Phase 2 (2026-11-09): fixed in a47e5d6. Encoder maps the first frame's color space by name to an encoded gamut (Display P3 family incl. linear/extended -> P3; everything else incl. DeviceRGB/untagged -> sRGB), draws in encoded sRGB or Display P3 (never DeviceRGB or linear), and writes one per-gamut triple to every pixel buffer (.shouldPropagate) and to AVVideoColorPropertiesKey: sRGB = BT.709 / IEC_sRGB / BT.709; P3 = P3_D65 / IEC_sRGB / BT.709. Readback: track extensions carry the triple for H.264 and HEVC; ffmpeg trace_headers shows the SPS VUI writes primaries 1 or 12, transfer 13, matrix 1, video_full_range_flag 0 for both codecs, and the colr nclx atom matches. Decode: sRGB (204,51,26) within 3 at 39x77 and 768x768; P3 export reads back as P3 within 3 (not clipped); gray 128 exact. Media filter 110 tests + 23 pipeline tests green with sentinels skipped. AC #3 (just check) is the lead's.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
MP4 frames are drawn in the grid's encoded gamut and tagged sRGB 1/13/1 or Display P3 12/13/1 (video range) through AVVideoColorPropertiesKey and matching CVPixelBuffer attachments, for H.264 and HEVC; verified in the bitstream VUI with ffmpeg trace_headers. The first frame decides the gamut for a mixed sequence. GIF export and the media phase stay green; no goldens moved. Full local gate passed at batch c43c3fb (media 163/37). Not verified: player/browser display of transfer function 13.
<!-- SECTION:FINAL_SUMMARY:END -->
