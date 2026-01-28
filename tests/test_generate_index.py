import subprocess
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from scripts.generate_index import (
    generate_package_index,
    generate_root_index,
    generate_indexes,
    parse_wheel_filename,
)


class ParseWheelFilenameTests(unittest.TestCase):
    def test_normalizes_name_and_handles_build_tag(self) -> None:
        info = parse_wheel_filename(
            "Flash.Attn_extra-2.5.0-1-cp312-cp312-manylinux2014_x86_64.whl"
        )

        self.assertEqual(
            info,
            {
                "name": "flash-attn-extra",
                "version": "2.5.0",
                "build": "1",
                "python": "cp312",
                "abi": "cp312",
                "platform": "manylinux2014_x86_64",
            },
        )

    def test_rejects_invalid_names(self) -> None:
        with self.assertRaises(ValueError):
            parse_wheel_filename("not-a-wheel.txt")


class GeneratePackageIndexTests(unittest.TestCase):
    def test_uses_base_url_without_double_slash(self) -> None:
        wheel_name = "flash_attn-2.5.0-cp312-cp312-linux_x86_64.whl"

        html = generate_package_index(
            package_name="flash-attn",
            wheels=(wheel_name,),
            base_url="https://example.com/releases/",
        )

        self.assertIn(
            'href="https://example.com/releases/flash_attn-2.5.0-cp312-cp312-linux_x86_64.whl"',
            html,
        )
        self.assertTrue(html.startswith("<!DOCTYPE html>"))


class GenerateIndexesTests(unittest.TestCase):
    def test_creates_root_and_package_indexes(self) -> None:
        with TemporaryDirectory() as tmp_dir:
            tmp_path = Path(tmp_dir)
            wheels_dir = tmp_path / "wheels"
            wheels_dir.mkdir(parents=True, exist_ok=True)

            wheel_files = (
                "flash_attn-2.5.0-cp312-cp312-linux_x86_64.whl",
                "xformers-0.0.23-1-cp311-cp311-manylinux2014_x86_64.whl",
            )

            for wheel in wheel_files:
                (wheels_dir / wheel).write_bytes(b"")

            output_dir = tmp_path / "simple"
            summary = generate_indexes(
                wheels_dir=wheels_dir,
                output_dir=output_dir,
                base_url="https://example.com/releases",
            )

            root_index = (output_dir / "index.html").read_text()
            flash_index = (output_dir / "flash-attn" / "index.html").read_text()

            self.assertIn("flash-attn", summary["packages"])
            self.assertIn("xformers", summary["packages"])
            self.assertIn('<a href="flash-attn/">', root_index)
            self.assertIn(
                "flash_attn-2.5.0-cp312-cp312-linux_x86_64.whl",
                flash_index,
            )

    def test_script_runs_end_to_end(self) -> None:
        with TemporaryDirectory() as tmp_dir:
            tmp_path = Path(tmp_dir)
            wheels_dir = tmp_path / "wheels"
            wheels_dir.mkdir(parents=True, exist_ok=True)
            (wheels_dir / "flash_attn-2.5.0-cp312-cp312-linux_x86_64.whl").write_bytes(
                b""
            )

            output_dir = tmp_path / "simple"

            result = subprocess.run(
                [
                    sys.executable,
                    "scripts/generate_index.py",
                    "--wheels-dir",
                    str(wheels_dir),
                    "--output-dir",
                    str(output_dir),
                    "--base-url",
                    "https://example.com/releases",
                ],
                capture_output=True,
                text=True,
            )

            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertTrue((output_dir / "index.html").exists())
            self.assertTrue((output_dir / "flash-attn" / "index.html").exists())


if __name__ == "__main__":
    unittest.main()
