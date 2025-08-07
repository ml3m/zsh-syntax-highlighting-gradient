# -------------------------------------------------------------------------------------------------
# Copyright (c) zsh-syntax-highlighting contributors
# All rights reserved.
# -------------------------------------------------------------------------------------------------
# -*- mode: zsh; sh-indentation: 2; indent-tabs-mode: nil; sh-basic-offset: 2; -*-
# vim: ft=zsh sw=2 ts=2 et
# -------------------------------------------------------------------------------------------------

# A simple gradient highlighter that applies a per-character color gradient
# to configured tokens as you type (e.g., "sudo").
#
# Notes:
# - We color by emitting one-character regions with different fg colors.
# - We intentionally write to region_highlight directly for per-character control.
# - Colors use named/256-color values supported by zle's region_highlight (fg=...).

# Default configuration (user may override these in their zshrc)
# Tokens to apply gradient to (exact substring match).
: ${ZSH_HIGHLIGHT_GRADIENT_TOKENS:=(sudo)}

# Palette for gradient stops (cycled/interpolated across token length).
# Use color names or 256-color numbers (e.g., 196, 208, 226, 46, 51, 21, 93, 201).
: ${ZSH_HIGHLIGHT_GRADIENT_PALETTE:=(red yellow green cyan blue magenta)}

# Whether to only match whole words. If "on", token must be delimited by non-word chars.
: ${ZSH_HIGHLIGHT_GRADIENT_WORD_BOUNDARY:=off}

# Whether to ignore case when searching tokens.
: ${ZSH_HIGHLIGHT_GRADIENT_IGNORE_CASE:=off}


# Return 0 when the highlighter should run
_zsh_highlight_highlighter_gradient_predicate()
{
  emulate -L zsh
  setopt localoptions noxtrace noverbose
  _zsh_highlight_buffer_modified
}


# Internal: case folding helper
_zsh_highlight_gradient__maybe_fold()
{
  emulate -L zsh
  setopt localoptions noxtrace noverbose
  # $1: string
  if [[ ${ZSH_HIGHLIGHT_GRADIENT_IGNORE_CASE} == on ]]; then
    print -r -- "${1:l}"
  else
    print -r -- "$1"
  fi
}


# Internal: emit one-character region with a given color
_zsh_highlight_gradient__emit_char()
{
  # $1: start (0-based index into BUFFER)
  # $2: color (e.g., red or 196)
  local -i start=$1
  local color=$2
  region_highlight+=("$start $(( start + 1 )) fg=$color, memo=zsh-syntax-highlighting")
}


# Internal: for a token of length L and character index i, pick a palette color
_zsh_highlight_gradient__color_for_index()
{
  # $1: char index i (0..L-1)
  # $2: token length L
  # outputs chosen color name/number
  local -i i=$1
  local -i len=$2
  local -a palette=( "${(@)ZSH_HIGHLIGHT_GRADIENT_PALETTE}" )
  local -i stops=${#palette}

  if (( stops <= 1 || len <= 1 )); then
    print -r -- "${palette[1]:-default}"
    return
  fi

  # Map i in [0, len-1] to palette index in [1, stops] using integer arithmetic
  # idx = floor(i*(stops-1)/(len-1)) + 1
  local -i numerator=$(( i * (stops - 1) ))
  local -i denominator=$(( len - 1 ))
  local -i idx=$(( numerator / denominator + 1 ))
  # Clamp just in case of rounding at end
  if (( idx < 1 )); then idx=1; fi
  if (( idx > stops )); then idx=stops; fi
  print -r -- "${palette[idx]}"
}


# Internal: find all non-overlapping occurrences of "needle" in "haystack" and call a callback
_zsh_highlight_gradient__for_each_occurrence()
{
  emulate -L zsh
  setopt localoptions extendedglob noxtrace noverbose
  # $1: haystack string
  # $2: needle string (exact substring)
  # $3: callback(name) that takes (start0, end0) with 0-based indices
  local haystack=$1
  local needle=$2
  local callback=$3

  local folded_haystack=$(_zsh_highlight_gradient__maybe_fold "$haystack")
  local folded_needle=$(_zsh_highlight_gradient__maybe_fold "$needle")

  local -i hlen=${#folded_haystack}
  local -i nlen=${#folded_needle}
  if (( nlen == 0 || hlen == 0 || nlen > hlen )); then
    return
  fi

  local -i offset=1   # zsh strings are 1-based for slicing
  while (( offset <= hlen - nlen + 1 )); do
    # Compare literal substring (case-already-folded)
    local segment=${folded_haystack[offset,offset+nlen-1]}
    if [[ $segment != "$folded_needle" ]]; then
      (( offset++ ))
      continue
    fi
    local -i abs=$offset

    # Word boundary check if requested (inline to avoid xtrace of assignments)
    if [[ ${ZSH_HIGHLIGHT_GRADIENT_WORD_BOUNDARY} == on ]]; then
      if [[ ${folded_haystack[abs-1,abs-1]:-" "} == [[:alnum:]_] || \
            ${folded_haystack[abs+nlen,abs+nlen]:-" "} == [[:alnum:]_] ]]; then
        offset=$(( abs + nlen ))
        continue
      fi
    fi

    # Convert 1-based zsh indices to 0-based start/end (exclusive)
    local -i start0=$(( abs - 1 ))
    local -i end0=$(( start0 + nlen ))
    "${callback}" $start0 $end0

    offset=$(( abs + nlen ))
  done
}


# The paint function
_zsh_highlight_highlighter_gradient_paint()
{
  emulate -L zsh
  setopt localoptions extendedglob noxtrace noverbose

  local buf=$BUFFER
  local -i buflen=${#BUFFER}
  local -a tokens=( "${(@)ZSH_HIGHLIGHT_GRADIENT_TOKENS}" )

  # Collect all spans for configured tokens
  typeset -ga _ZSH_HIGHLIGHT_GRADIENT_SPANS
  _ZSH_HIGHLIGHT_GRADIENT_SPANS=()

  local token
  for token in "$tokens[@]"; do
    _zsh_highlight_gradient__for_each_occurrence "$buf" "$token" _zsh_highlight_gradient__collect_span
  done

  # Build a mask of positions to paint
  typeset -A _zsh_highlight_gradient_paint_mask
  _zsh_highlight_gradient_paint_mask=()
  local -i j start0 end0 i
  for (( j = 1; j <= ${#_ZSH_HIGHLIGHT_GRADIENT_SPANS}; j += 2 )); do
    start0=${_ZSH_HIGHLIGHT_GRADIENT_SPANS[j]}
    end0=${_ZSH_HIGHLIGHT_GRADIENT_SPANS[j+1]}
    for (( i = start0; i < end0; i++ )); do
      _zsh_highlight_gradient_paint_mask[$i]=1
    done
  done

  # Apply one continuous gradient only across matched spans (min_start..max_end)
  # Compute overall span boundaries
  local -i min_start=2147483647
  local -i max_end=-1
  for (( j = 1; j <= ${#_ZSH_HIGHLIGHT_GRADIENT_SPANS}; j += 2 )); do
    local -i s=${_ZSH_HIGHLIGHT_GRADIENT_SPANS[j]}
    local -i e=${_ZSH_HIGHLIGHT_GRADIENT_SPANS[j+1]}
    (( s < min_start )) && min_start=$s
    (( e > max_end )) && max_end=$e
  done

  local -i total_len=$(( max_end - min_start ))
  (( total_len <= 0 )) && return

  # Only positions marked in the mask are painted; color index is offset from min_start
  for (( i = min_start; i < max_end; i++ )); do
    if [[ -n ${_zsh_highlight_gradient_paint_mask[$i]:-} ]]; then
      local color=$(_zsh_highlight_gradient__color_for_index $(( i - min_start )) $total_len)
      _zsh_highlight_gradient__emit_char $i "$color"
    fi
  done
}


# Callback used by _for_each_occurrence
_zsh_highlight_gradient__paint_span()
{
  # $1: start0, $2: end0 (exclusive), 0-based
  local -i start0=$1
  local -i end0=$2
  local -i len=$(( end0 - start0 ))
  local -i i
  for (( i = 0; i < len; i++ )); do
    local color=$(_zsh_highlight_gradient__color_for_index $i $len)
    _zsh_highlight_gradient__emit_char $(( start0 + i )) "$color"
  done
}

# Collect spans callback (start0, end0 exclusive); used to build mask
_zsh_highlight_gradient__collect_span()
{
  local -i start0=$1
  local -i end0=$2
  _ZSH_HIGHLIGHT_GRADIENT_SPANS+=($start0 $end0)
}

