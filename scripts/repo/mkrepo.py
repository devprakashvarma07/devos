#!/usr/bin/env python3
"""Build an APT repository tree from a directory of .deb files.

Output layout (served as static files, e.g. GitHub Pages):

    repo/dists/stable/Release
    repo/dists/stable/InRelease        (created by build-repo.sh)
    repo/dists/stable/Release.gpg      (created by build-repo.sh)
    repo/dists/stable/main/binary-amd64/Packages{,.gz,.xz}
    repo/dists/stable/main/binary-amd64/by-hash/SHA256/<hash>
    repo/pool/main/<p>/<package>/<file>.deb
"""

import datetime
import email.utils
import gzip
import hashlib
import lzma
import os
import shutil
import subprocess
import sys

SUITE = "stable"
COMPONENT = "main"
ARCH = "amd64"


def run(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout


def read_control(deb):
    """Return the deb control fields with their continuation lines intact."""
    text = run("dpkg-deb", "-f", deb).rstrip("\n")
    fields = []
    for line in text.split("\n"):
        if line[:1] in (" ", "\t") and fields:
            fields[-1][1] += "\n" + line
        elif ":" in line:
            key, value = line.split(":", 1)
            fields.append([key.strip(), value.lstrip()])
    return fields


def get(fields, key):
    for k, v in fields:
        if k == key:
            return v
    return ""


def set_field(fields, key, value):
    for item in fields:
        if item[0] == key:
            item[1] = value
            return
    fields.append([key, value])


def sha(path, algo):
    h = hashlib.new(algo)
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: mkrepo.py <debs-dir> <repo-out>")

    debs_dir, out = sys.argv[1], sys.argv[2]
    debs = sorted(
        os.path.join(debs_dir, f)
        for f in os.listdir(debs_dir)
        if f.endswith(".deb")
    )
    if not debs:
        sys.exit("no .deb files found in " + debs_dir)

    dist = os.path.join(out, "dists", SUITE)
    index_dir = os.path.join(dist, COMPONENT, "binary-" + ARCH)
    pool = os.path.join(out, "pool", COMPONENT)

    for path in (dist, index_dir, pool):
        shutil.rmtree(path, ignore_errors=True)
        os.makedirs(path, exist_ok=True)

    stanzas = []
    for deb in debs:
        fields = read_control(deb)
        name = get(fields, "Package")
        if not name:
            sys.exit("missing Package field: " + deb)

        # pool/main/<first letter>/<package>/<file>
        rel = os.path.join(
            "pool", COMPONENT, name[0], name, os.path.basename(deb)
        )
        dst = os.path.join(out, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy2(deb, dst)

        size = os.path.getsize(dst)
        set_field(fields, "Filename", rel)
        set_field(fields, "Size", str(size))
        set_field(fields, "MD5sum", sha(dst, "md5"))
        set_field(fields, "SHA1", sha(dst, "sha1"))
        set_field(fields, "SHA256", sha(dst, "sha256"))
        stanzas.append("\n".join(f"{k}: {v}" for k, v in fields))

    packages = "\n\n".join(stanzas) + "\n"
    raw = packages.encode()

    indices = {
        "Packages": raw,
        "Packages.gz": gzip.compress(raw, compresslevel=9, mtime=0),
        "Packages.xz": lzma.compress(raw, preset=9 | lzma.PRESET_EXTREME),
    }

    sums = {"MD5Sum": "md5", "SHA1": "sha1", "SHA256": "sha256"}
    digest = {algo: [] for algo in sums.values()}

    for name, data in indices.items():
        path = os.path.join(index_dir, name)
        with open(path, "wb") as fh:
            fh.write(data)
        for algo in digest:
            digest[algo].append(
                (hashlib.new(algo, data).hexdigest(), len(data), f"{COMPONENT}/binary-{ARCH}/{name}")
            )
        by_hash = os.path.join(index_dir, "by-hash", "SHA256")
        os.makedirs(by_hash, exist_ok=True)
        shutil.copy2(path, os.path.join(by_hash, hashlib.sha256(data).hexdigest()))

    now = datetime.datetime.now(datetime.timezone.utc)
    date = email.utils.format_datetime(now)
    valid_until = email.utils.format_datetime(now + datetime.timedelta(days=30))

    lines = [
        "Origin: DevOS",
        "Label: DevOS",
        "Suite: " + SUITE,
        "Codename: " + SUITE,
        "Version: 1.0",
        "Date: " + date,
        "Valid-Until: " + valid_until,
        "Architectures: " + ARCH,
        "Components: " + COMPONENT,
        "Description: DevOS package archive",
        "Acquire-By-Hash: yes",
    ]
    for label, algo in sums.items():
        lines.append(label + ":")
        for checksum, size, name in digest[algo]:
            lines.append(f" {checksum} {size} {name}")

    with open(os.path.join(dist, "Release"), "w") as fh:
        fh.write("\n".join(lines) + "\n")

    print(f"repo built: {len(debs)} package(s)")
    for name, data in indices.items():
        print(f"  {COMPONENT}/binary-{ARCH}/{name}  {len(data)} bytes")


if __name__ == "__main__":
    main()
