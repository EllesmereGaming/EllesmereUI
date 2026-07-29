with open('Compatibility/Atlas.lua', 'r') as f:
    lines = f.readlines()
with open('Compatibility/Atlas.lua', 'w') as f:
    f.writelines(lines[1:])
