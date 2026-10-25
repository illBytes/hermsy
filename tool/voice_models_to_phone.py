#!/usr/bin/env python3
"""Puts Hermsy's voice models on the phone over USB, instead of the phone
downloading them again.

    python3 tool/voice_models_to_phone.py --app com.illbytes.hermsy_app.dev
    python3 tool/voice_models_to_phone.py --shared

The models (Silero, Parakeet, both Kokoros, about 1.5 GB) are downloaded
once to ~/HermsyVoiceModels, each checked against the SHA-256 pinned in
lib/services/voice_models.dart, and unpacked. Then:

  --app PKG   copies them into that app's own model folder. Only works for
              a debug build (Hermsy Dev): Android lets adb into its files.
  --shared    copies them to the phone's Download/Hermsy voice models
              folder, for Settings > Voice models > Import from a folder
              in any Hermsy, including the one from Google Play.
"""
import argparse
import hashlib
import os
import re
import subprocess
import sys
import tarfile
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = os.path.join(ROOT, 'lib', 'services', 'voice_models.dart')
CACHE = os.path.expanduser('~/HermsyVoiceModels')
DOWNLOADS = os.path.join(CACHE, 'downloads')
MODELS = os.path.join(CACHE, 'voice_models')
ADB = os.path.expanduser('~/Library/Android/sdk/platform-tools/adb')
SHARED = '/sdcard/Download/Hermsy voice models'


def catalog():
    """(folder, [files]) for every model, read from the app's own catalog."""
    text = open(CATALOG).read()
    consts = dict(re.findall(r"const (_\w+) =\s*'([^']+)';", text))

    def expand(value):
        return re.sub(r'\$(_\w+)', lambda m: consts[m.group(1)], value)

    models = []
    for block in re.split(r'\bVoiceModel\(', text)[1:]:
        folder = re.search(r"folder:\s*'([^']+)'|folder:\s*(_\w+)", block)
        if folder is None:
            continue  # the class's own constructor, not a model
        folder = folder.group(1) or consts[folder.group(2)]
        files = []
        for entry in re.split(r'\bModelFile\(', block)[1:]:
            get = lambda key: re.search(key + r":\s*'([^']+)'", entry, re.S)
            files.append({
                'url': expand(get('url').group(1)),
                'path': expand(get('path').group(1)),
                'size': int(re.search(r'size:\s*(\d+)', entry).group(1)),
                'sha256': re.search(r"sha256:\s*'([0-9a-f]{64})'", entry).group(1),
                'archive': 'archive: true' in entry,
            })
        models.append((expand(folder), files))
    return models


def sha256(path):
    digest = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            digest.update(chunk)
    return digest.hexdigest()


def fetch(file):
    dest = os.path.join(DOWNLOADS, file['path'])
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    if os.path.exists(dest) and os.path.getsize(dest) == file['size']:
        return dest
    print(f"  downloading {os.path.basename(dest)} ({file['size'] / 1e6:.0f} MB)")
    part = dest + '.part'
    have = os.path.getsize(part) if os.path.exists(part) else 0
    request = urllib.request.Request(file['url'], headers={'Range': f'bytes={have}-'} if have else {})
    with urllib.request.urlopen(request) as response, open(part, 'ab' if have else 'wb') as out:
        if have and response.status != 206:
            out.truncate(0)
        while chunk := response.read(1 << 20):
            out.write(chunk)
    os.replace(part, dest)
    return dest


def prepare():
    for folder, files in catalog():
        ready = os.path.join(MODELS, folder, '.ready')
        if os.path.exists(ready):
            print(f'{folder}: ready')
            continue
        print(f'{folder}:')
        for file in files:
            path = fetch(file)
            if sha256(path) != file['sha256']:
                os.remove(path)
                sys.exit(f"  {file['path']} failed its checksum; run again to re-download")
            if file['archive']:
                print('  unpacking')
                with tarfile.open(path, 'r:bz2') as archive:
                    archive.extractall(MODELS, filter='data')
            else:
                target = os.path.join(MODELS, file['path'])
                os.makedirs(os.path.dirname(target), exist_ok=True)
                if os.path.exists(target):
                    os.remove(target)
                os.link(path, target)
        with open(ready, 'w') as marker:
            marker.write('ok')
        print('  verified')


def adb(*args, check=True):
    # The connected phone, or the one SERIAL names when several are.
    serial = os.environ.get('SERIAL')
    return subprocess.run([ADB, *(['-s', serial] if serial else []), *args], check=check)


def to_app(package):
    tmp = '/data/local/tmp/hermsy_voice_models'
    print(f'Copying to {package}…')
    # Stopped first, so a download the app started cannot write over the copy.
    adb('shell', 'am', 'force-stop', package)
    adb('shell', 'rm', '-rf', tmp)
    adb('push', MODELS, tmp)
    adb('shell', 'chmod', '-R', 'a+rX', tmp)
    # adb joins its arguments into one line for the phone's shell, so the
    # command for run-as goes as one quoted string. Half-finished downloads
    # (.part files) are cleared away.
    script = (
        f'mkdir -p files/voice_models && cp -R {tmp}/. files/voice_models/ && '
        'find files/voice_models -name "*.part" -delete'
    )
    adb('shell', f"run-as {package} sh -c '{script}'")
    adb('shell', 'rm', '-rf', tmp)
    print('Done: open the app and voice is ready.')


def to_shared():
    print(f'Copying to {SHARED}…')
    # Quoted for the phone's shell: the folder name has spaces. A fresh
    # folder each time, so adb push fills it rather than nesting inside it.
    adb('shell', f'rm -rf "{SHARED}"')
    adb('push', MODELS, SHARED)
    print('Done: in Hermsy, Settings > Voice > Voice models > Import from a folder.')


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('--app', help='a debug app to copy into, e.g. com.illbytes.hermsy_app.dev')
    parser.add_argument('--shared', action='store_true', help='copy to Download on the phone')
    args = parser.parse_args()
    prepare()
    if args.app:
        to_app(args.app)
    if args.shared:
        to_shared()


main()
