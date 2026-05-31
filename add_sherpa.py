#!/usr/bin/env python3
"""Patch the generated Govorun.xcodeproj/project.pbxproj to add sherpa-onnx.xcframework."""

import re
import os

PBXPROJ = "Govorun.xcodeproj/project.pbxproj"

# Fixed UUIDs for reproducibility
FILE_REF_UUID    = "AA000001000000000000001A"  # PBXFileReference
BUILD_FILE_UUID  = "AA000001000000000000001B"  # PBXBuildFile (Frameworks phase)

SHERPA_PATH = "$(PROJECT_DIR)/Frameworks/sherpa-onnx.xcframework"

def patch():
    with open(PBXPROJ, "r") as f:
        content = f.read()

    # 1. Add PBXFileReference entry
    file_ref = (
        f'\t\t{FILE_REF_UUID} /* sherpa-onnx.xcframework */ = '
        f'{{isa = PBXFileReference; lastKnownFileType = wrapper.xcframework; '
        f'name = "sherpa-onnx.xcframework"; path = "{SHERPA_PATH}"; sourceTree = "<group>"; }};\n'
    )
    if FILE_REF_UUID not in content:
        content = content.replace(
            "/* End PBXFileReference section */",
            file_ref + "\t\t/* End PBXFileReference section */"
        )

    # 2. Add PBXBuildFile entry
    build_file = (
        f'\t\t{BUILD_FILE_UUID} /* sherpa-onnx.xcframework in Frameworks */ = '
        f'{{isa = PBXBuildFile; fileRef = {FILE_REF_UUID} /* sherpa-onnx.xcframework */; }};\n'
    )
    if BUILD_FILE_UUID not in content:
        content = content.replace(
            "/* End PBXBuildFile section */",
            build_file + "\t\t/* End PBXBuildFile section */"
        )

    # 3. Add to PBXGroup (Frameworks group) — find it and add the file ref
    # Add to the first PBXGroup that contains 'children'
    # We look for the group that has "Frameworks" or just add to a general group
    frameworks_group_pattern = re.compile(
        r'(name = Frameworks;\s*sourceTree = "<group>";\s*})', re.DOTALL
    )

    # Instead, find the main group and add a Frameworks group entry
    # Add the file ref to a group — find any 'children' list and inject
    # Simplest: find the products group and add before it
    # Actually just add to the root group's children

    # Find the first 'children = (' block and add our ref
    sherpa_child = f'\t\t\t\t{FILE_REF_UUID} /* sherpa-onnx.xcframework */,\n'

    # Find PBXFrameworksBuildPhase and add the build file to 'files'
    frameworks_phase_pattern = re.compile(
        r'(isa = PBXFrameworksBuildPhase;.*?files = \()(.*?)(\);)',
        re.DOTALL
    )

    def add_to_frameworks(m):
        before = m.group(1)
        files = m.group(2)
        after = m.group(3)
        entry = f'\t\t\t\t{BUILD_FILE_UUID} /* sherpa-onnx.xcframework in Frameworks */,\n'
        if BUILD_FILE_UUID not in files:
            files = entry + files
        return before + files + after

    if BUILD_FILE_UUID not in content:
        content = frameworks_phase_pattern.sub(add_to_frameworks, content)

    # Add file ref to some group for Xcode navigation (find main group's children)
    group_children_pattern = re.compile(
        r'(name = Frameworks;.*?children = \()(.*?)(\);)',
        re.DOTALL
    )
    def add_to_group(m):
        before = m.group(1)
        children = m.group(2)
        after = m.group(3)
        if FILE_REF_UUID not in children:
            children = f'\t\t\t\t{FILE_REF_UUID} /* sherpa-onnx.xcframework */,\n' + children
        return before + children + after

    if FILE_REF_UUID not in content:
        content = group_children_pattern.sub(add_to_group, content, count=1)

    with open(PBXPROJ, "w") as f:
        f.write(content)

    print("✅ Patched pbxproj with sherpa-onnx.xcframework")

if __name__ == "__main__":
    os.chdir(os.path.dirname(os.path.abspath(__file__)))
    patch()
