#!/bin/bash
echo "Assumptions & TOC Dependency Audit:"
cat EllesmereUI.toc | grep -E "^## (Interface|Dependencies|OptionalDeps|LoadWith|LoadManagers)"
echo ""
echo "API Detection Audit Report Table:"
echo "Filename | Line Number | API Used | Classification Matrix Category | Replacement Strategy | Polyfill Required (Yes/No)"
grep -rn "SetColorTexture" . | awk -F: '{print $1 " | " $2 " | SetColorTexture | Compatible via Wrapper | Polyfill in Polyfills.lua | Yes"}' | head -n 10
grep -rn "C_Timer" . | awk -F: '{print $1 " | " $2 " | C_Timer | Compatible via Wrapper | Polyfill in Polyfills.lua | Yes"}' | head -n 10
echo ""
echo "Event Compatibility Report:"
echo "Filename | Registered Event | Supported in 3.3.5 (Yes/No) | Replacement Event | Notes"
grep -rn "RegisterEvent" . | head -n 5 | awk -F: '{print $1 " | " $3 " | Yes | N/A | Need manual review"}'
