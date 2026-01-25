# Video Extension Guide using HunyuanVideo-1.5

This guide explains how to extend the buildings.mp4 video using the HunyuanVideo-1.5 model.

## How It Works

The extension process uses **Image-to-Video (I2V)** mode:
1. Extracts the last frame from your video
2. Uses that frame as input to HunyuanVideo-1.5 I2V model
3. Generates a continuation video (default: 5 seconds)
4. Concatenates the original and extended videos

## Prerequisites

### System Requirements
- **GPU**: NVIDIA GPU with at least 14GB VRAM (recommended)
  - RTX 3090/4090, A100, H100, or similar
- **CPU Mode**: Will work but extremely slow (not recommended)
- **RAM**: 16GB+ recommended
- **Python**: 3.10 or later

### Installation

1. **Install PyTorch with CUDA** (if you have an NVIDIA GPU):
```bash
# For CUDA 12.1
pip3 install torch torchvision --index-url https://download.pytorch.org/whl/cu121

# For CUDA 11.8
pip3 install torch torchvision --index-url https://download.pytorch.org/whl/cu118

# For CPU only (very slow, not recommended)
pip3 install torch torchvision
```

2. **Install other dependencies**:
```bash
pip install -r requirements_video.txt
```

3. **Optional - Install Flash Attention** (for faster inference):
```bash
pip install flash-attn --no-build-isolation
```

## Usage

### Basic Usage

Extend the buildings video with default settings:

```bash
python extend_video.py --input website/assets/buildings.mp4 --output website/assets/buildings_extended.mp4
```

### With Custom Prompt

Provide a specific prompt to guide the extension:

```bash
python extend_video.py \
  --input website/assets/buildings.mp4 \
  --output website/assets/buildings_extended.mp4 \
  --prompt "Camera slowly zooms out revealing more of the cityscape, golden hour lighting, cinematic movement"
```

### Adjust Generation Length

Generate a longer extension (241 frames = ~10 seconds):

```bash
python extend_video.py \
  --input website/assets/buildings.mp4 \
  --output website/assets/buildings_extended.mp4 \
  --frames 241 \
  --prompt "Smooth camera pan across the buildings"
```

### High Quality Settings

Use more inference steps for better quality:

```bash
python extend_video.py \
  --input website/assets/buildings.mp4 \
  --output website/assets/buildings_extended.mp4 \
  --steps 100 \
  --prompt "Continue the architectural tour with smooth cinematic camera movement"
```

### Use 720p Model

For higher resolution (requires more VRAM):

```bash
python extend_video.py \
  --input website/assets/buildings.mp4 \
  --output website/assets/buildings_extended.mp4 \
  --model "hunyuanvideo-community/HunyuanVideo-1.5-Diffusers-720p_i2v"
```

## All Command Line Options

| Option | Default | Description |
|--------|---------|-------------|
| `--input` | Required | Path to input video |
| `--output` | `extended_video.mp4` | Path for output video |
| `--prompt` | Auto-generated | Text describing desired continuation |
| `--model` | `480p_i2v` | Model variant (480p or 720p) |
| `--frames` | 121 (~5s) | Number of frames to generate |
| `--steps` | 50 | Inference steps (higher = better quality) |
| `--seed` | 42 | Random seed for reproducibility |

## Available Models

All models are downloaded automatically from HuggingFace:

- `hunyuanvideo-community/HunyuanVideo-1.5-Diffusers-480p_i2v` (default, 14GB VRAM)
- `hunyuanvideo-community/HunyuanVideo-1.5-Diffusers-720p_i2v` (higher quality, 20GB+ VRAM)

## Tips for Best Results

### 1. **Write Detailed Prompts**
Instead of just "continue", describe:
- Camera movement (pan, zoom, dolly, static)
- Lighting conditions
- Atmosphere and mood
- Specific actions or changes

Good example:
```
"Slow camera pan to the right revealing more modern skyscrapers,
golden hour lighting with warm tones, cinematic smooth movement,
architectural photography style"
```

### 2. **Frame Count Guidelines**
- 61 frames = ~2.5 seconds
- 121 frames = ~5 seconds (default)
- 241 frames = ~10 seconds (maximum)

### 3. **Quality vs Speed**
- Fast: `--steps 30` (lower quality)
- Balanced: `--steps 50` (default)
- High quality: `--steps 100` (slower)

### 4. **Memory Management**

If you get Out of Memory (OOM) errors:

```bash
# Enable memory optimization
export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True,max_split_size_mb:128

# Then run the script
python extend_video.py --input website/assets/buildings.mp4
```

## Troubleshooting

### Issue: "CUDA out of memory"
**Solution**:
- Use 480p model instead of 720p
- Reduce `--frames` (e.g., 61 instead of 121)
- Enable memory optimization (see above)
- Close other GPU applications

### Issue: Very slow generation
**Solution**:
- Ensure you're using GPU (check with `nvidia-smi`)
- Install Flash Attention
- Use fewer inference steps (`--steps 30`)

### Issue: Poor quality extension
**Solution**:
- Increase `--steps` to 100
- Write a more detailed prompt
- Try different seeds (`--seed 123`)
- Use 720p model if you have enough VRAM

### Issue: Model download is slow
**Solution**:
Models are large (several GB). First run will download and cache them.
You can also pre-download:
```bash
huggingface-cli download hunyuanvideo-community/HunyuanVideo-1.5-Diffusers-480p_i2v
```

## Example Workflow

Here's a complete example extending your buildings video:

```bash
# 1. Check GPU availability
nvidia-smi

# 2. Set memory optimization
export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True,max_split_size_mb:128

# 3. Run extension with custom prompt
python extend_video.py \
  --input website/assets/buildings.mp4 \
  --output website/assets/buildings_extended.mp4 \
  --prompt "Cinematic camera movement slowly panning across the modern architecture, golden hour warm lighting, smooth and professional cinematography" \
  --frames 121 \
  --steps 50

# 4. Check the result
open website/assets/buildings_extended.mp4  # macOS
# or: xdg-open website/assets/buildings_extended.mp4  # Linux
```

## Expected Timeline

On RTX 4090 (24GB VRAM):
- Model download (first time only): 5-10 minutes
- 480p, 121 frames, 50 steps: ~3-5 minutes
- 720p, 121 frames, 50 steps: ~8-12 minutes

On RTX 3090 (24GB VRAM):
- 480p, 121 frames, 50 steps: ~5-8 minutes
- 720p, 121 frames, 50 steps: ~15-20 minutes

## Further Resources

- [HunyuanVideo-1.5 GitHub](https://github.com/Tencent-Hunyuan/HunyuanVideo-1.5)
- [HuggingFace Model Card](https://huggingface.co/tencent/HunyuanVideo-1.5)
- [Prompt Writing Guide](https://github.com/Tencent-Hunyuan/HunyuanVideo-1.5/blob/main/assets/HunyuanVideo_1_5_Prompt_Handbook_EN.md)
