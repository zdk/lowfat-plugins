# lowfat-plugins

Community plugins for [`lowfat`](https://github.com/) — a token-aware command filter for LLMs.

| Plugin | Commands |
| --- | --- |
| [`terraform/terraform-compact`](terraform/terraform-compact) | `terraform`, `tf`, `tofu` |

## Usage

```sh
# 1. install — auto-discovered under ~/.lowfat/plugins/<category>/<name>/
git clone https://github.com/zdk/lowfat-plugins.git ~/.lowfat/plugins

# 2. trust + verify
lowfat plugin trust terraform-compact
lowfat plugin list

# 3. run
lowfat terraform plan
eval "$(lowfat shell-init zsh)"   # or bash — auto-wraps tf/tofu/terraform
```

Tune output: `lowfat level {ultra|full|lite}`. Bench savings: `lowfat plugin bench <name>`.

## New plugin

```sh
lowfat plugin new <category>/<name>
```
