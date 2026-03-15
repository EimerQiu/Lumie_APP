"""Docker sandbox management for running AI-generated analysis code.

Handles container creation, execution monitoring, result collection,
and cleanup.
"""
import asyncio
import base64
import json
import logging
import shutil
from pathlib import Path
from typing import Optional

from ..core.config import settings

logger = logging.getLogger(__name__)

_SANDBOX_IMAGE = "lumie-analysis-sandbox"
_SANDBOX_BASE_DIR = Path("/tmp/lumie_sandbox")


def _ensure_sandbox_dir(job_id: str) -> Path:
    """Create and return the sandbox directory for a job."""
    job_dir = _SANDBOX_BASE_DIR / job_id
    output_dir = job_dir / "output"
    output_dir.mkdir(parents=True, exist_ok=True)
    return job_dir


def _write_code_file(job_dir: Path, code: str) -> Path:
    """Write the generated Python code to main.py in the job directory."""
    code_path = job_dir / "main.py"
    code_path.write_text(code, encoding="utf-8")
    return code_path


async def run_in_sandbox(
    job_id: str,
    code: str,
    target_user_id: str,
    timeout_sec: int = 30,
) -> dict:
    """Run generated code in a Docker sandbox container.

    Args:
        job_id: Unique job identifier.
        code: Python code to execute.
        target_user_id: The user ID whose data to analyze.
        timeout_sec: Maximum execution time in seconds.

    Returns:
        Dict with keys: success, result, stdout, stderr, container_id, error.
    """
    job_dir = _ensure_sandbox_dir(job_id)
    _write_code_file(job_dir, code)

    output_dir = job_dir / "output"
    code_path = job_dir / "main.py"

    if not settings.SANDBOX_MONGO_URI:
        return {
            "success": False,
            "result": None,
            "stdout": "",
            "stderr": "",
            "container_id": "",
            "error": "SANDBOX_MONGO_URI not configured",
        }

    # Build docker run command
    docker_cmd = [
        "docker", "run",
        "--rm",
        "--name", f"lumie-analysis-{job_id[:12]}",
        "--memory", "256m",
        "--cpu-quota", "50000",
        "--pids-limit", "32",
        "--network", "bridge",
        "--read-only",
        "--tmpfs", "/tmp:size=64m,noexec",
        "-v", f"{code_path}:/app/main.py:ro",
        "-v", f"{output_dir}:/output:rw",
        "-e", f"MONGO_URI={settings.SANDBOX_MONGO_URI}",
        "-e", f"TARGET_USER_ID={target_user_id}",
        _SANDBOX_IMAGE,
    ]

    container_id = f"lumie-analysis-{job_id[:12]}"
    stdout_data = ""
    stderr_data = ""

    try:
        process = await asyncio.create_subprocess_exec(
            *docker_cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )

        try:
            stdout_bytes, stderr_bytes = await asyncio.wait_for(
                process.communicate(),
                timeout=timeout_sec,
            )
            stdout_data = stdout_bytes.decode("utf-8", errors="replace")
            stderr_data = stderr_bytes.decode("utf-8", errors="replace")
        except asyncio.TimeoutError:
            # Kill the container on timeout
            logger.warning(f"Sandbox timeout for job {job_id}, killing container")
            kill_proc = await asyncio.create_subprocess_exec(
                "docker", "kill", container_id,
                stdout=asyncio.subprocess.DEVNULL,
                stderr=asyncio.subprocess.DEVNULL,
            )
            await kill_proc.wait()
            return {
                "success": False,
                "result": None,
                "stdout": stdout_data,
                "stderr": stderr_data,
                "container_id": container_id,
                "error": "timeout",
            }

        if process.returncode != 0:
            logger.error(f"Sandbox failed for job {job_id}: exit={process.returncode}")
            return {
                "success": False,
                "result": None,
                "stdout": stdout_data,
                "stderr": stderr_data,
                "container_id": container_id,
                "error": f"exit_code_{process.returncode}: {stderr_data[:500]}",
            }

        # Read results
        result = _read_results(output_dir)

        return {
            "success": True,
            "result": result,
            "stdout": stdout_data,
            "stderr": stderr_data,
            "container_id": container_id,
            "error": None,
        }

    except Exception as e:
        logger.error(f"Sandbox execution error for job {job_id}: {e}")
        return {
            "success": False,
            "result": None,
            "stdout": stdout_data,
            "stderr": stderr_data,
            "container_id": container_id,
            "error": str(e),
        }


def _read_results(output_dir: Path) -> Optional[dict]:
    """Read result.json and optional chart.png from the output directory."""
    result_path = output_dir / "result.json"
    chart_path = output_dir / "chart.png"

    if not result_path.exists():
        logger.warning("No result.json found in sandbox output")
        return None

    try:
        result = json.loads(result_path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, UnicodeDecodeError) as e:
        logger.error(f"Failed to parse result.json: {e}")
        return None

    # Attach chart as base64 if it exists
    if chart_path.exists():
        try:
            chart_bytes = chart_path.read_bytes()
            result["chart_base64"] = base64.b64encode(chart_bytes).decode("ascii")
        except Exception as e:
            logger.warning(f"Failed to read chart.png: {e}")

    return result


def cleanup_sandbox(job_id: str) -> None:
    """Remove the sandbox temp directory for a job."""
    job_dir = _SANDBOX_BASE_DIR / job_id
    if job_dir.exists():
        shutil.rmtree(str(job_dir), ignore_errors=True)
        logger.info(f"Cleaned up sandbox dir for job {job_id}")


async def kill_container(job_id: str) -> None:
    """Kill a running sandbox container by job ID."""
    container_name = f"lumie-analysis-{job_id[:12]}"
    try:
        proc = await asyncio.create_subprocess_exec(
            "docker", "kill", container_name,
            stdout=asyncio.subprocess.DEVNULL,
            stderr=asyncio.subprocess.DEVNULL,
        )
        await proc.wait()
        logger.info(f"Killed container {container_name}")
    except Exception as e:
        logger.warning(f"Failed to kill container {container_name}: {e}")
