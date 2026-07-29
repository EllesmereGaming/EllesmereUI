with open('EllesmereUI.toc', 'r') as f:
    lines = f.readlines()

new_lines = []
for line in lines:
    if "Polyfills.lua" in line:
        new_lines.append("Compatibility/API.lua\n")
        new_lines.append("Compatibility/Frame.lua\n")
        new_lines.append("Compatibility/Texture.lua\n")
        new_lines.append("Compatibility/Cooldown.lua\n")
        new_lines.append("Compatibility/Atlas.lua\n")
        new_lines.append("Compatibility/Secure.lua\n")
        new_lines.append("Compatibility/Layout.lua\n")
        new_lines.append("Compatibility/Timer.lua\n")
    else:
        new_lines.append(line)

with open('EllesmereUI.toc', 'w') as f:
    f.writelines(new_lines)
