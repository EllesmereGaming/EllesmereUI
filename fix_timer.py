import re

with open('Compatibility/Timer.lua', 'r') as f:
    content = f.read()

# Extract only the C_Timer part
timer_part = re.search(r'-- 2\. C_Timer Polyfill.*?end\nend', content, re.DOTALL)
if timer_part:
    with open('Compatibility/Timer.lua', 'w') as f:
        f.write("-- Timer.lua\n\n" + timer_part.group(0) + "\n")
