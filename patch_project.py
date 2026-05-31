#!/usr/bin/env python3
"""Complete pbxproj patcher: adds Frameworks + Resources build phases and sherpa-onnx."""

import re, os

PBXPROJ = "Govorun.xcodeproj/project.pbxproj"

# Fixed UUIDs for idempotency
SHERPA_FILE_REF    = "AA000001000000000000001A"
SHERPA_BUILD_FILE  = "AA000001000000000000001B"
SETUP_SCRIPT_PHASE = "AA000001000000000000002A"
SOURCES_PHASE      = "3EAA675EA0DC57A70D9AA65E"
RESOURCES_PHASE    = "AA000001000000000000002B"
ASSETS_FILE_REF    = "AA000001000000000000002C"
ASSETS_BUILD_FILE  = "AA000001000000000000002D"
MODEL_FILE_REF     = "AA000001000000000000002E"
MODEL_BUILD_FILE   = "AA000001000000000000002F"

SHERPA_ABS = os.path.abspath("Frameworks/sherpa-onnx.xcframework")

SETUP_SCRIPT = (
    '#!/bin/sh\\n'
    'set -e\\n'
    'SHERPA=\\"${PROJECT_DIR}/Frameworks/sherpa-onnx.xcframework/macos-arm64_x86_64\\"\\n'
    'mkdir -p \\"${BUILT_PRODUCTS_DIR}/include\\"\\n'
    'rsync -r \\"${SHERPA}/Headers/\\" \\"${BUILT_PRODUCTS_DIR}/include/\\"\\n'
    'cp -f \\"${SHERPA}/libsherpa-onnx.a\\" \\"${BUILT_PRODUCTS_DIR}/libsherpa-onnx.a\\"\\n'
    'echo sherpa-onnx prepared'
)

def patch():
    with open(PBXPROJ) as f:
        c = f.read()

    # ── 1. PBXBuildFile entries ──────────────────────────────────────────────
    new_bf = ""
    if ASSETS_BUILD_FILE not in c:
        new_bf += (
            f'\t\t{ASSETS_BUILD_FILE} /* Assets.xcassets in Resources */ = '
            f'{{isa = PBXBuildFile; fileRef = {ASSETS_FILE_REF} /* Assets.xcassets */; }};\n'
        )
    if MODEL_BUILD_FILE not in c:
        new_bf += (
            f'\t\t{MODEL_BUILD_FILE} /* Model in Resources */ = '
            f'{{isa = PBXBuildFile; fileRef = {MODEL_FILE_REF} /* Model */; }};\n'
        )
    if new_bf:
        c = c.replace("/* End PBXBuildFile section */",
                      new_bf + "\t\t/* End PBXBuildFile section */")

    # ── 2. PBXFileReference entries ─────────────────────────────────────────
    new_fr = ""
    assets_ref_marker = f'{ASSETS_FILE_REF} /* Assets.xcassets */ = {{isa = PBXFileReference'
    model_ref_marker  = f'{MODEL_FILE_REF} /* Model */ = {{isa = PBXFileReference'
    if assets_ref_marker not in c:
        new_fr += (
            f'\t\t{ASSETS_FILE_REF} /* Assets.xcassets */ = '
            f'{{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; '
            f'path = Assets.xcassets; sourceTree = "<group>"; }};\n'
        )
    if model_ref_marker not in c:
        new_fr += (
            f'\t\t{MODEL_FILE_REF} /* Model */ = '
            f'{{isa = PBXFileReference; lastKnownFileType = folder; '
            f'path = Govorun/Resources/Model; sourceTree = "<group>"; }};\n'
        )
    if new_fr:
        c = c.replace("/* End PBXFileReference section */",
                      new_fr + "\t\t/* End PBXFileReference section */")

    # ── 3. PBXShellScriptBuildPhase — copies sherpa headers/lib ────────────
    if SETUP_SCRIPT_PHASE not in c:
        script_phase = (
            f'/* Begin PBXShellScriptBuildPhase section */\n'
            f'\t\t{SETUP_SCRIPT_PHASE} /* Prepare sherpa-onnx */ = {{\n'
            f'\t\t\tisa = PBXShellScriptBuildPhase;\n'
            f'\t\t\talwaysOutOfDate = 1;\n'
            f'\t\t\tbuildActionMask = 2147483647;\n'
            f'\t\t\tfiles = ();\n'
            f'\t\t\tinputPaths = ();\n'
            f'\t\t\tname = "Prepare sherpa-onnx";\n'
            f'\t\t\toutputPaths = ();\n'
            f'\t\t\trunOnlyForDeploymentPostprocessing = 0;\n'
            f'\t\t\tshellPath = /bin/sh;\n'
            f'\t\t\tshellScript = "{SETUP_SCRIPT}";\n'
            f'\t\t\tshowEnvVarsInLog = 0;\n'
            f'\t\t}};\n'
            f'/* End PBXShellScriptBuildPhase section */\n\n'
        )
        c = c.replace("/* Begin PBXSourcesBuildPhase section */",
                      script_phase + "/* Begin PBXSourcesBuildPhase section */")

    # ── 4. PBXResourcesBuildPhase ───────────────────────────────────────────
    if RESOURCES_PHASE not in c:
        resources_phase = (
            f'\n/* Begin PBXResourcesBuildPhase section */\n'
            f'\t\t{RESOURCES_PHASE} /* Resources */ = {{\n'
            f'\t\t\tisa = PBXResourcesBuildPhase;\n'
            f'\t\t\tbuildActionMask = 2147483647;\n'
            f'\t\t\tfiles = (\n'
            f'\t\t\t\t{ASSETS_BUILD_FILE} /* Assets.xcassets in Resources */,\n'
            f'\t\t\t\t{MODEL_BUILD_FILE} /* Model in Resources */,\n'
            f'\t\t\t);\n'
            f'\t\t\trunOnlyForDeploymentPostprocessing = 0;\n'
            f'\t\t}};\n'
            f'/* End PBXResourcesBuildPhase section */\n'
        )
        c = c.replace("/* End PBXSourcesBuildPhase section */",
                      "/* End PBXSourcesBuildPhase section */" + resources_phase)

    # ── 5. Update target buildPhases ─────────────────────────────────────────
    c = re.sub(
        r'(buildPhases = \()(\s*' + SOURCES_PHASE + r' /\* Sources \*/,\s*)(\);)',
        lambda m: (
            f'buildPhases = (\n'
            f'\t\t\t\t\t{SETUP_SCRIPT_PHASE} /* Prepare sherpa-onnx */,\n'
            f'\t\t\t\t\t{SOURCES_PHASE} /* Sources */,\n'
            f'\t\t\t\t\t{RESOURCES_PHASE} /* Resources */,\n'
            f'\t\t\t\t);'
        ) if SETUP_SCRIPT_PHASE not in m.group(0) else m.group(0),
        c
    )

    # ── 6. Add OTHER_LDFLAGS for sherpa static lib ───────────────────────────
    # Find target Debug config and add flag if not present
    ldflag = '-lsherpa-onnx'
    if ldflag not in c:
        c = c.replace(
            'CODE_SIGN_ENTITLEMENTS = Govorun/Govorun.entitlements;\n'
            '\t\t\t\tCODE_SIGN_IDENTITY = "-";',
            'CODE_SIGN_ENTITLEMENTS = Govorun/Govorun.entitlements;\n'
            '\t\t\t\tCODE_SIGN_IDENTITY = "-";\n'
            f'\t\t\t\tOTHER_LDFLAGS = "$(inherited) -lsherpa-onnx -lc++";',
        )

    # ── 7. Add file refs to Govorun group for navigation ────────────────────
    govorun_end = (
        '\t\t\t\t9ACD4F69C9C127D5ED673C84 /* Paste */,\n'
        '\t\t\t\tC72ACE564DD0AD3BA91177FB /* Settings */,\n'
        '\t\t\t\t91B95F9D8D45C04B1AAB0765 /* UI */,\n'
        '\t\t\t);'
    )
    govorun_end_new = (
        '\t\t\t\t9ACD4F69C9C127D5ED673C84 /* Paste */,\n'
        '\t\t\t\tC72ACE564DD0AD3BA91177FB /* Settings */,\n'
        '\t\t\t\t91B95F9D8D45C04B1AAB0765 /* UI */,\n'
        f'\t\t\t\t{ASSETS_FILE_REF} /* Assets.xcassets */,\n'
        f'\t\t\t\t{MODEL_FILE_REF} /* Model */,\n'
        '\t\t\t);'
    )
    if govorun_end in c:
        c = c.replace(govorun_end, govorun_end_new)

    with open(PBXPROJ, "w") as f:
        f.write(c)
    print("✅  pbxproj fully patched")


if __name__ == "__main__":
    os.chdir(os.path.dirname(os.path.abspath(__file__)))
    patch()
