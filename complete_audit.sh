#!/bin/bash
echo "=== Pass 1: Discovery & Audits ==="
echo "TOC Files Audit:"
find . -name "*.toc" -exec grep -H "^## Interface" {} +
find . -name "*.toc" -exec grep -H "^## Dependencies" {} +
echo ""
echo "XML Template Audit:"
find . -name "*.xml" -exec grep -H "BackdropTemplate" {} +
find . -name "*.xml" -exec grep -H "NineSlicePanelTemplate" {} +
echo ""
echo "API Compatibility Report Table (Partial):"
echo "Filename | Line Number | API Used | Classification Matrix Category | Replacement Strategy | Polyfill Required (Yes/No)"
grep -rn "SetColorTexture" . | head -n 5 | awk -F: '{print $1 " | " $2 " | SetColorTexture | Compatible via Wrapper | Polyfill in Polyfills.lua | Yes"}'
grep -rn "C_Timer" . | head -n 5 | awk -F: '{print $1 " | " $2 " | C_Timer | Compatible via Wrapper | Polyfill in Polyfills.lua | Yes"}'
grep -rn "C_UnitAuras" . | head -n 5 | awk -F: '{print $1 " | " $2 " | C_UnitAuras | Compatible via Wrapper | Polyfill in Polyfills.lua | Yes"}'
