# My project Working Agreements

Use `C:/ProjectsRoot/Unity_1/AGENTS.md` for shared rules. Read it once if it is absent from the active instruction chain; the Git root may exclude this parent directory from automatic discovery.

- This is the main Unity project. Read `ProjectSettings/ProjectVersion.txt` for the actual version; do not infer APIs from the old H02 project or the V1.1 branch.
- Historical lookup only when needed: `C:/ProjectsRoot/Unity_1/design_tmp/README.md`.
- GM work: read `C:/ProjectsRoot/Unity_1/design_tmp/gm_panel/00_角色与规范索引.md` and the relevant project patch. UI asset work: read `C:/ProjectsRoot/Unity_1/design_tmp/字体与UI规范/UI_预制体制作与交付规范.md`.

## Fresh clone setup (keys and fonts)
- Lua protection keys: the repo stores `Assets/Game/Scripts/Security/LuaProtectionKeys.cs` with EMPTY values on purpose. The real AES key and RSA modulus exist only on the owner's machine as an uncommitted local change. After a fresh clone, run Unity menu `Tools/Security/Initialize Lua protection keys` before building protected Lua or AssetBundles. It reads or creates the signing secret outside the workspace (`%USERPROFILE%/.codex/build-secrets/my-project-lua-v1/signing-key.json`, or the absolute path in `UNITY_LUA_SIGNING_KEY_PATH`) and fills the file. Never commit the filled file and never commit the signing secret. EditMode tests and the lint gate do not need the real keys.
- Chinese UI font: `Assets/Game/Resources/Fonts/AlibabaPuHuiTiSDF.asset` (~24 MB) is not in git and not in LFS. Regenerate it with `Docs/字体重新生成.md`. Without it, Chinese UI text in a fresh clone renders as missing glyphs; lint and EditMode do not depend on it.
