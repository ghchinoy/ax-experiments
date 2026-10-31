#!/usr/bin/env python3
# Copyright 2026 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""AX Swarm Agent worker script.

Reads structured agent configuration from the in-sandbox AX loopback metadata
server ($AX_METADATA_URL/metadata/v1alpha1/ax/task -> spec.config) or from
environment variables (AGENT_ROLE, AGENT_PROMPT, AX_AGENT_MODEL), invokes
Gemini, and writes output to both stdout and a structured file.
"""

import os
import sys
import urllib.request
import warnings
from pathlib import Path

warnings.filterwarnings("ignore")


def load_task_config():
    """Fetches spec.config from the in-sandbox loopback metadata endpoint."""
    meta_url = os.environ.get("AX_METADATA_URL", "http://127.0.0.1:8099")
    url = f"{meta_url.rstrip('/')}/metadata/v1alpha1/ax/task"
    raw_yaml = ""
    try:
        with urllib.request.urlopen(url, timeout=1.5) as resp:
            if resp.status == 200:
                raw_yaml = resp.read().decode("utf-8")
    except Exception:
        raw_yaml = os.environ.get("AX_TASK_YAML", "")

    if not raw_yaml:
        return {}

    try:
        import yaml  # type: ignore

        doc = yaml.safe_load(raw_yaml) or {}
        spec = doc.get("spec") or {}
        cfg = spec.get("config") or {}
        if isinstance(cfg, dict):
            return cfg
    except Exception:
        pass
    return {}


def main():
    api_key = os.environ.get("GEMINI_API_KEY")
    if not api_key:
        print("ERROR: GEMINI_API_KEY environment variable is not set.", file=sys.stderr)
        sys.exit(1)

    cfg = load_task_config()

    role = os.environ.get("AGENT_ROLE") or cfg.get("role") or "Assistant"
    user_prompt = (
        os.environ.get("AGENT_PROMPT")
        or cfg.get("prompt")
        or "Introduce yourself and report your environment."
    )
    model_name = (
        os.environ.get("AX_AGENT_MODEL")
        or cfg.get("model")
        or "gemini-3.8-flash"
    )
    input_file = os.environ.get("INPUT_FILE") or cfg.get("inputFile")
    output_file = (
        os.environ.get("OUTPUT_FILE")
        or cfg.get("outputFile")
        or "/workspace/out/result.md"
    )

    context_text = ""
    if input_file and os.path.exists(input_file):
        try:
            with open(input_file, "r", encoding="utf-8") as f:
                context_text = f"\n\n--- Context from {input_file} ---\n" + f.read()
        except Exception as e:
            print(f"Warning: could not read input file {input_file}: {e}", file=sys.stderr)

    system_instruction = (
        f"You are an AI agent in a multi-agent swarm running inside an isolated sandbox container. "
        f"Your specific role in this swarm is: {role}.\n"
        f"Be direct, precise, concise, and focused on your assigned role."
    )

    full_prompt = f"{user_prompt}{context_text}"

    try:
        from google import genai

        client = genai.Client(api_key=api_key)
        response = client.models.generate_content(
            model=model_name,
            contents=full_prompt,
            config={"system_instruction": system_instruction},
        )
        reply = response.text or ""
    except Exception as e:
        print(f"ERROR calling Gemini model {model_name}: {e}", file=sys.stderr)
        sys.exit(2)

    out_path = Path(output_file)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(reply)

    print(reply)


if __name__ == "__main__":
    main()
