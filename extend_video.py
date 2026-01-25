"""
Video Extension Script using HunyuanVideo-1.5
This script extends a video by:
1. Extracting the last frame from the source video
2. Using HunyuanVideo-1.5's I2V mode to generate a continuation
3. Concatenating the original and extended videos
"""

import torch
import cv2
import numpy as np
from pathlib import Path
import argparse
from PIL import Image

# Monkey patch for PyTorch 2.2.2 compatibility with diffusers 0.36.0
# This adds a dummy xpu module to avoid import errors
if not hasattr(torch, 'xpu'):
    class DummyXPU:
        @staticmethod
        def empty_cache():
            pass
        @staticmethod
        def device_count():
            return 0
        @staticmethod
        def is_available():
            return False
        @staticmethod
        def manual_seed(seed):
            pass
        @staticmethod
        def set_device(device):
            pass
        @staticmethod
        def get_device():
            return None
    torch.xpu = DummyXPU()

from diffusers import HunyuanVideo15Pipeline
from diffusers.utils import export_to_video


def extract_last_frame(video_path: str, output_path: str = "last_frame.jpg") -> str:
    """Extract the last frame from a video file."""
    print(f"Extracting last frame from {video_path}...")

    cap = cv2.VideoCapture(video_path)

    # Get total frames
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    fps = cap.get(cv2.CAP_PROP_FPS)

    print(f"Video info: {total_frames} frames at {fps} FPS")

    # Set position to last frame
    cap.set(cv2.CAP_PROP_POS_FRAMES, total_frames - 1)

    # Read the last frame
    ret, frame = cap.read()

    if ret:
        # Convert BGR to RGB
        frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        # Save as image
        Image.fromarray(frame_rgb).save(output_path)
        print(f"Last frame saved to {output_path}")
    else:
        raise ValueError("Could not read last frame from video")

    cap.release()
    return output_path


def extend_video_with_hunyuan(
    input_video: str,
    prompt: str = None,
    model_path: str = "hunyuanvideo-community/HunyuanVideo-1.5-Diffusers-480p_i2v",
    num_frames: int = 121,
    num_inference_steps: int = 50,
    seed: int = 42,
    output_path: str = "extended_video.mp4"
):
    """
    Extend a video using HunyuanVideo-1.5's Image-to-Video mode.

    Args:
        input_video: Path to input video file
        prompt: Text prompt describing the continuation (if None, auto-generated)
        model_path: HuggingFace model path
        num_frames: Number of frames to generate (121 = ~5 seconds at 24fps)
        num_inference_steps: Quality setting (higher = better, slower)
        seed: Random seed for reproducibility
        output_path: Path for output extended video
    """

    # Step 1: Extract last frame
    print("\n" + "="*60)
    print("STEP 1: Extracting last frame from video")
    print("="*60)
    frame_path = extract_last_frame(input_video, "temp_last_frame.jpg")

    # Step 2: Set up HunyuanVideo pipeline
    print("\n" + "="*60)
    print("STEP 2: Loading HunyuanVideo-1.5 model")
    print("="*60)
    print(f"Model: {model_path}")

    # Detect best available device
    if torch.cuda.is_available():
        device = "cuda:0"
        dtype = torch.bfloat16
        print("Using CUDA GPU acceleration")
    elif torch.backends.mps.is_available():
        device = "mps"
        dtype = torch.float16  # MPS works better with float16
        print("Using Apple Silicon (MPS) GPU acceleration")
    else:
        device = "cpu"
        dtype = torch.float32
        print("WARNING: No GPU acceleration available. This will be very slow on CPU!")

    pipe = HunyuanVideo15Pipeline.from_pretrained(
        model_path,
        torch_dtype=dtype
    )

    # Enable optimizations based on device
    if device == "cuda:0":
        pipe.enable_model_cpu_offload()
        pipe.vae.enable_tiling()
        print("Enabled model CPU offload and VAE tiling for memory efficiency")
    elif device == "mps":
        # MPS doesn't support cpu_offload, so move to device directly
        pipe = pipe.to(device)
        pipe.vae.enable_tiling()
        print("Enabled VAE tiling for memory efficiency")
    else:
        pipe = pipe.to(device)

    # Step 3: Generate continuation
    print("\n" + "="*60)
    print("STEP 3: Generating video continuation")
    print("="*60)

    # Auto-generate prompt if not provided
    if prompt is None:
        prompt = "Continue the scene with smooth camera movement, maintaining the same visual style and atmosphere, natural progression and coherent motion"

    print(f"Prompt: {prompt}")
    print(f"Generating {num_frames} frames ({num_frames/24:.1f} seconds at 24fps)")
    print(f"Inference steps: {num_inference_steps}")
    print(f"Seed: {seed}")

    # Load the last frame as PIL Image
    init_image = Image.open(frame_path)

    generator = torch.Generator(device=device).manual_seed(seed)

    # Generate video continuation
    result = pipe(
        prompt=prompt,
        image=init_image,
        num_frames=num_frames,
        num_inference_steps=num_inference_steps,
        generator=generator,
    )

    video_frames = result.frames[0]

    # Step 4: Export continuation
    print("\n" + "="*60)
    print("STEP 4: Exporting continuation")
    print("="*60)

    continuation_path = "temp_continuation.mp4"
    export_to_video(video_frames, continuation_path, fps=24)
    print(f"Continuation saved to {continuation_path}")

    # Step 5: Concatenate videos
    print("\n" + "="*60)
    print("STEP 5: Concatenating original and extended videos")
    print("="*60)

    concatenate_videos(input_video, continuation_path, output_path)

    print("\n" + "="*60)
    print("COMPLETE!")
    print("="*60)
    print(f"Extended video saved to: {output_path}")

    # Cleanup
    Path(frame_path).unlink(missing_ok=True)
    Path(continuation_path).unlink(missing_ok=True)
    print("Temporary files cleaned up")


def concatenate_videos(video1: str, video2: str, output: str):
    """Concatenate two videos using OpenCV."""
    print(f"Concatenating {video1} + {video2} -> {output}")

    # Open both videos
    cap1 = cv2.VideoCapture(video1)
    cap2 = cv2.VideoCapture(video2)

    # Get properties from first video
    fps = int(cap1.get(cv2.CAP_PROP_FPS))
    width = int(cap1.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap1.get(cv2.CAP_PROP_FRAME_HEIGHT))

    # Create video writer
    fourcc = cv2.VideoWriter_fourcc(*'mp4v')
    out = cv2.VideoWriter(output, fourcc, fps, (width, height))

    # Write frames from first video
    while True:
        ret, frame = cap1.read()
        if not ret:
            break
        out.write(frame)

    # Write frames from second video (resize if needed)
    while True:
        ret, frame = cap2.read()
        if not ret:
            break
        # Resize if dimensions don't match
        if frame.shape[:2] != (height, width):
            frame = cv2.resize(frame, (width, height))
        out.write(frame)

    # Cleanup
    cap1.release()
    cap2.release()
    out.release()

    print(f"Videos concatenated successfully!")


def main():
    parser = argparse.ArgumentParser(description="Extend a video using HunyuanVideo-1.5")
    parser.add_argument("--input", type=str, required=True, help="Input video path")
    parser.add_argument("--output", type=str, default="extended_video.mp4", help="Output video path")
    parser.add_argument("--prompt", type=str, default=None, help="Text prompt for continuation")
    parser.add_argument("--model", type=str,
                       default="hunyuanvideo-community/HunyuanVideo-1.5-Diffusers-480p_i2v",
                       help="HuggingFace model path (use *_i2v for image-to-video)")
    parser.add_argument("--frames", type=int, default=121, help="Number of frames to generate (121 = ~5s)")
    parser.add_argument("--steps", type=int, default=50, help="Inference steps (quality)")
    parser.add_argument("--seed", type=int, default=42, help="Random seed")

    args = parser.parse_args()

    extend_video_with_hunyuan(
        input_video=args.input,
        prompt=args.prompt,
        model_path=args.model,
        num_frames=args.frames,
        num_inference_steps=args.steps,
        seed=args.seed,
        output_path=args.output
    )


if __name__ == "__main__":
    main()
