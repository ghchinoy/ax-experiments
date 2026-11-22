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

# Renders semantic Graphviz .dot diagrams in diagrams/ into light and dark WebP
# assets using the Luminous Graphviz gvpr theme (~/projects/graphviz-style).

GRAPHVIZ_STYLE_DIR ?= $(abspath ../../graphviz-style)
THEME := $(GRAPHVIZ_STYLE_DIR)/theme/luminous.gvpr
GVPR ?= /opt/homebrew/bin/gvpr
DOT ?= /opt/homebrew/bin/dot

DOTS := $(sort $(wildcard diagrams/*.dot))
LIGHT_WEBPS := $(DOTS:.dot=-light.webp)
DARK_WEBPS := $(DOTS:.dot=-dark.webp)
PNGS := $(DOTS:.dot=-light.png) $(DOTS:.dot=-dark.png)

.PHONY: all png clean

all: $(LIGHT_WEBPS) $(DARK_WEBPS)

diagrams/%-light.webp: diagrams/%.dot $(THEME)
	$(GVPR) -c -f $(THEME) -a light $< | $(DOT) -Twebp -o $@

diagrams/%-dark.webp: diagrams/%.dot $(THEME)
	$(GVPR) -c -f $(THEME) -a dark $< | $(DOT) -Twebp -o $@

png: $(PNGS)

diagrams/%-light.png: diagrams/%.dot $(THEME)
	$(GVPR) -c -f $(THEME) -a light $< | $(DOT) -Tpng -o $@

diagrams/%-dark.png: diagrams/%.dot $(THEME)
	$(GVPR) -c -f $(THEME) -a dark $< | $(DOT) -Tpng -o $@

clean:
	rm -f diagrams/*-light.png diagrams/*-dark.png
