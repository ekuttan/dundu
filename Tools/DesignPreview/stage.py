"""Stage an isolated in-memory UI preview; never changes the real app."""
from pathlib import Path
import shutil
import sys

root = Path(__file__).resolve().parents[2]
target = Path(sys.argv[1] if len(sys.argv) > 1 else '/private/tmp/dundu-design-preview')
if target.resolve() == root.resolve():
    raise ValueError('The preview directory must be separate from the source project.')
target.mkdir(parents=True, exist_ok=True)
for name in ('iOS', 'Shared', 'Dundu.xcodeproj'):
    shutil.copytree(root / name, target / name, dirs_exist_ok=True)
    if name in ('iOS', 'Shared'):
        for staged in (target / name).rglob('*.swift'):
            if not (root / name / staged.relative_to(target / name)).exists():
                staged.unlink()
packages = target / 'Packages'
if not packages.exists():
    packages.symlink_to(root / 'Packages', target_is_directory=True)
(target / 'macOS').mkdir(exist_ok=True)
shutil.copyfile(root / 'Tools/DesignPreview/DunduPreviewApp.swift', target / 'iOS/DunduApp.swift')
print(target)
