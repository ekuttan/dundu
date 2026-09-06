"""Capture staged preview routes on a booted Simulator using sample data."""
from pathlib import Path
import subprocess
import sys
import time

out = Path(sys.argv[1]).resolve()
device = sys.argv[2] if len(sys.argv) > 2 else 'booted'
out.mkdir(parents=True, exist_ok=True)
app = 'app.scoop.dundu.designpreview'

def sim(*args, check=True):
    return subprocess.run(['xcrun', 'simctl', *args], check=check, capture_output=True, text=True)

appearance = sim('ui', device, 'appearance').stdout.strip()
size = sim('ui', device, 'content_size').stdout.strip()
try:
    sim('install', device, '/private/tmp/dundu-preview-build/Build/Products/Debug-iphonesimulator/Dundu.app')
    sim('ui', device, 'appearance', 'light')
    sim('ui', device, 'content_size', 'large')
    for route in ['reminders', 'today', 'inbox', 'settings', 'edit', 'onboarding']:
        sim('terminate', device, app, check=False)
        time.sleep(0.5)
        sim('launch', device, app, route)
        time.sleep(5)
        sim('io', device, 'screenshot', str(out / f'{route}.png'))
    sim('ui', device, 'appearance', 'dark')
    sim('terminate', device, app, check=False)
    sim('launch', device, app, 'reminders')
    time.sleep(5)
    sim('io', device, 'screenshot', str(out / 'reminders-dark.png'))
    sim('ui', device, 'appearance', 'light')
    sim('ui', device, 'content_size', 'accessibility-medium')
    sim('terminate', device, app, check=False)
    time.sleep(0.5)
    sim('launch', device, app, 'reminders')
    time.sleep(5)
    sim('io', device, 'screenshot', str(out / 'reminders-large-type.png'))
finally:
    if appearance in ('light', 'dark'):
        sim('ui', device, 'appearance', appearance)
    sim('ui', device, 'content_size', size)
print(out)
