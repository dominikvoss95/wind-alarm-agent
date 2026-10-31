"""
Script to register alarm_sound.mp3 in the iOS Xcode project.
This enables custom notification sounds for iOS without needing Xcode.
"""
import re
import os

def main():
    file_path = "app/ios/Runner.xcodeproj/project.pbxproj"
    if not os.path.exists(file_path):
        print(f"Error: {file_path} not found.")
        return

    with open(file_path, "r", encoding="utf-8") as f:
        content = f.read()

    # Define unique UUIDs for our new entries (24 hex characters)
    build_file_id = "F3123456294A63AB00263BE5"
    file_ref_id = "F3123457294A63AB00263BE5"

    # 1. Add to PBXBuildFile section
    build_file_entry = f"\t\t{build_file_id} /* alarm_sound.mp3 in Resources */ = {{isa = PBXBuildFile; fileRef = {file_ref_id} /* alarm_sound.mp3 */; }};\n"
    if "alarm_sound.mp3 in Resources" not in content:
        content = content.replace("/* Begin PBXBuildFile section */\n", "/* Begin PBXBuildFile section */\n" + build_file_entry)
        print("Added to PBXBuildFile section.")

    # Path is relative to the Runner group (path = Runner). A "Runner/" prefix
    # resolves to ios/Runner/Runner/alarm_sound.mp3, which Xcode cannot open.
    file_ref_entry = f"\t\t{file_ref_id} /* alarm_sound.mp3 */ = {{isa = PBXFileReference; lastKnownFileType = audio.mp3; path = alarm_sound.mp3; sourceTree = \"<group>\"; }};\n"
    bad_ref = '{isa = PBXFileReference; lastKnownFileType = audio.mp3; name = alarm_sound.mp3; path = Runner/alarm_sound.mp3; sourceTree = "<group>"; }'
    good_ref = '{isa = PBXFileReference; lastKnownFileType = audio.mp3; path = alarm_sound.mp3; sourceTree = "<group>"; }'
    if bad_ref in content:
        content = content.replace(bad_ref, good_ref)
        print("Corrected alarm_sound.mp3 path (it is relative to the Runner group).")
    if "alarm_sound.mp3 */ = {isa = PBXFileReference" not in content:
        content = content.replace("/* Begin PBXFileReference section */\n", "/* Begin PBXFileReference section */\n" + file_ref_entry)
        print("Added to PBXFileReference section.")

    # 3. Add to PBXGroup section under Runner (97C146F01CF9000F007C117D)
    runner_group_match = re.search(r"97C146F01CF9000F007C117D /\* Runner \*/ = \{[^{]*children = \(([^)]*)\);", content, re.DOTALL)
    if runner_group_match:
        children_content = runner_group_match.group(1)
        if "alarm_sound.mp3" not in children_content:
            # Clean up empty lines and trailing spaces, then append
            lines = [line for line in children_content.splitlines() if line.strip()]
            lines.append(f"\t\t\t\t{file_ref_id} /* alarm_sound.mp3 */,")
            new_children_content = "\n" + "\n".join(lines) + "\n\t\t\t"
            old_group = runner_group_match.group(0)
            new_group = old_group.replace(children_content, new_children_content)
            content = content.replace(old_group, new_group)
            print("Added to PBXGroup (Runner children) section.")

    # 4. Add to PBXResourcesBuildPhase section (97C146EC1CF9000F007C117D)
    resources_phase_match = re.search(r"97C146EC1CF9000F007C117D /\* Resources \*/ = \{[^{]*files = \(([^)]*)\);", content, re.DOTALL)
    if resources_phase_match:
        files_content = resources_phase_match.group(1)
        if "alarm_sound.mp3" not in files_content:
            lines = [line for line in files_content.splitlines() if line.strip()]
            lines.append(f"\t\t\t\t{build_file_id} /* alarm_sound.mp3 in Resources */,")
            new_files_content = "\n" + "\n".join(lines) + "\n\t\t\t"
            old_phase = resources_phase_match.group(0)
            new_phase = old_phase.replace(files_content, new_files_content)
            content = content.replace(old_phase, new_phase)
            print("Added to PBXResourcesBuildPhase section.")

    with open(file_path, "w", encoding="utf-8") as f:
        f.write(content)
    print("Xcode project configuration updated successfully.")

if __name__ == "__main__":
    main()
