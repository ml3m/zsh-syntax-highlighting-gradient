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

# Palette-based mode: list of color stops (only used when MODE=palette).
# Use color names or 256-color numbers (e.g., 196, 208, 226, 46, 51, 21, 93, 201).
: ${ZSH_HIGHLIGHT_GRADIENT_PALETTE:=(224 187 151 150 153 189 183)}

# Pastel gradient mode (default): produce an aesthetic, close-knit gradient that
# expands smoothly with text length. For short text, colors are very close;
# for longer text, the hue span gradually increases (no big gaps).
# MODE can be "pastel" (default) or "palette".
: ${ZSH_HIGHLIGHT_GRADIENT_MODE:=pastel}

# Pastel tuning parameters
# Base hue in degrees [0,360). Choose a pleasing hue family to start from.
: ${ZSH_HIGHLIGHT_GRADIENT_BASE_HUE:=260}
# Saturation and Lightness (0..1) for a pastel look: low saturation, high lightness.
: ${ZSH_HIGHLIGHT_GRADIENT_PASTEL_SAT:=0.35}
: ${ZSH_HIGHLIGHT_GRADIENT_PASTEL_LIGHT:=0.85}
# How wide the hue range should be for short text (degrees). Keep small for tight look.
: ${ZSH_HIGHLIGHT_GRADIENT_BASE_SPAN_DEG:=20}
# How much to expand hue span per extra character (degrees per char).
: ${ZSH_HIGHLIGHT_GRADIENT_PER_CHAR_SPAN_DEG:=6}
# Maximum hue span (degrees). Prevents wrapping too much around the wheel.
: ${ZSH_HIGHLIGHT_GRADIENT_MAX_SPAN_DEG:=300}

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
  # $2: total length L across which the gradient is applied
  # outputs chosen 256-color index or color name
  emulate -L zsh
  setopt localoptions noxtrace noverbose

  local -i i=$1
  local -i len=$2

  # Fallback: if palette mode requested, use existing discrete mapping across stops
  if [[ ${ZSH_HIGHLIGHT_GRADIENT_MODE} == palette ]]; then
    local -a palette=( "${(@)ZSH_HIGHLIGHT_GRADIENT_PALETTE}" )
    local -i stops=${#palette}
    if (( stops <= 1 || len <= 1 )); then
      print -r -- "${palette[1]:-default}"
      return
    fi
    local -i numerator=$(( i * (stops - 1) ))
    local -i denominator=$(( len - 1 ))
    local -i idx=$(( numerator / denominator + 1 ))
    (( idx < 1 )) && idx=1
    (( idx > stops )) && idx=stops
    print -r -- "${palette[idx]}"
    return
  fi

  # Pastel mode: compute a soft, close-knit hue progression that expands with length
  # Handle trivial case
  if (( len <= 1 )); then
    local -i c
    c=$(_zsh_highlight_gradient__xterm256_from_hsl ${ZSH_HIGHLIGHT_GRADIENT_BASE_HUE} ${ZSH_HIGHLIGHT_GRADIENT_PASTEL_SAT} ${ZSH_HIGHLIGHT_GRADIENT_PASTEL_LIGHT})
    print -r -- "$c"
    return
  fi

  local -F hue_start=${ZSH_HIGHLIGHT_GRADIENT_BASE_HUE}
  local -F sat=${ZSH_HIGHLIGHT_GRADIENT_PASTEL_SAT}
  local -F light=${ZSH_HIGHLIGHT_GRADIENT_PASTEL_LIGHT}
  local -F base_span=${ZSH_HIGHLIGHT_GRADIENT_BASE_SPAN_DEG}
  local -F per_char=${ZSH_HIGHLIGHT_GRADIENT_PER_CHAR_SPAN_DEG}
  local -F max_span=${ZSH_HIGHLIGHT_GRADIENT_MAX_SPAN_DEG}

  # Compute hue span for given length; keep tight for very short, expand smoothly
  local -F span_deg
  if (( len <= 3 )); then
    span_deg=$base_span
  else
    span_deg=$(( base_span + (len - 3) * per_char ))
  fi
  # Clamp
  if (( span_deg > max_span )); then span_deg=$max_span; fi
  if (( span_deg < 0 )); then span_deg=0; fi

  # Position within span
  local -F step_deg=$(( span_deg / (len - 1.0) ))
  local -F hue=$(( hue_start + i * step_deg ))
  # Wrap hue to [0,360)
  while (( hue >= 360.0 )); do hue=$(( hue - 360.0 )); done
  while (( hue < 0.0 )); do hue=$(( hue + 360.0 )); done

  local -i color
  color=$(_zsh_highlight_gradient__xterm256_from_hsl $hue $sat $light)
  print -r -- "$color"
}

# Convert HSL (degrees, 0..1, 0..1) to nearest xterm-256 color index (16..231)
_zsh_highlight_gradient__xterm256_from_hsl()
{
  emulate -L zsh
  setopt localoptions noxtrace noverbose
  # $1 hue in degrees [0,360), $2 sat [0,1], $3 light [0,1]
  local -F H=$1
  local -F S=$2
  local -F L=$3

  # Normalize hue to [0,1]
  local -F h_norm=$H
  while (( h_norm >= 360.0 )); do h_norm=$(( h_norm - 360.0 )); done
  while (( h_norm < 0.0 )); do h_norm=$(( h_norm + 360.0 )); done
  local -F h_frac=$(( h_norm / 360.0 ))
  if (( S <= 0.0001 )); then
    # Gray
    local -F gray=L
    local -i v=$(( gray * 5.0 + 0.5 ))
    (( v < 0 )) && v=0
    (( v > 5 )) && v=5
    local -i idx=$(( 16 + 36 * v + 6 * v + v ))
    print -r -- "$idx"
    return
  fi

  local -F q p
  if (( L < 0.5 )); then
    q=$(( L * (1.0 + S) ))
  else
    q=$(( L + S - L * S ))
  fi
  p=$(( 2.0 * L - q ))

  # Helper values for hue to rgb conversion
  local -F t_r=$(( h_frac + 1.0/3.0 ))
  local -F t_g=$h_frac
  local -F t_b=$(( h_frac - 1.0/3.0 ))

  # Wrap to [0,1]
  for t in t_r t_g t_b; do
    local -F v
    v=${(P)t}
    while (( v < 0.0 )); do v=$(( v + 1.0 )); done
    while (( v > 1.0 )); do v=$(( v - 1.0 )); done
    typeset -F $t=$v
  done

  # Compute each RGB component from its t
  local -F r g b c x
  # r from t_r
  x=$t_r
  if (( x < 1.0/6.0 )); then
    c=$(( p + (q - p) * 6.0 * x ))
  elif (( x < 1.0/2.0 )); then
    c=$q
  elif (( x < 2.0/3.0 )); then
    c=$(( p + (q - p) * (2.0/3.0 - x) * 6.0 ))
  else
    c=$p
  fi
  r=$c
  # g from t_g
  x=$t_g
  if (( x < 1.0/6.0 )); then
    c=$(( p + (q - p) * 6.0 * x ))
  elif (( x < 1.0/2.0 )); then
    c=$q
  elif (( x < 2.0/3.0 )); then
    c=$(( p + (q - p) * (2.0/3.0 - x) * 6.0 ))
  else
    c=$p
  fi
  g=$c
  # b from t_b
  x=$t_b
  if (( x < 1.0/6.0 )); then
    c=$(( p + (q - p) * 6.0 * x ))
  elif (( x < 1.0/2.0 )); then
    c=$q
  elif (( x < 2.0/3.0 )); then
    c=$(( p + (q - p) * (2.0/3.0 - x) * 6.0 ))
  else
    c=$p
  fi
  b=$c

  # Map to 6x6x6 cube indices 0..5 with rounding
  local -i r5=$(( r * 5.0 + 0.5 ))
  local -i g5=$(( g * 5.0 + 0.5 ))
  local -i b5=$(( b * 5.0 + 0.5 ))
  (( r5 < 0 )) && r5=0; (( r5 > 5 )) && r5=5
  (( g5 < 0 )) && g5=0; (( g5 > 5 )) && g5=5
  (( b5 < 0 )) && b5=0; (( b5 > 5 )) && b5=5

  local -i idx=$(( 16 + 36 * r5 + 6 * g5 + b5 ))
  print -r -- "$idx"
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

  # Apply one continuous gradient across only the positions we actually paint.
  # This keeps adjacent painted characters close in color even if separated by gaps.
  local -a paint_positions
  paint_positions=()
  local -i min_start=2147483647
  local -i max_end=-1
  for (( j = 1; j <= ${#_ZSH_HIGHLIGHT_GRADIENT_SPANS}; j += 2 )); do
    local -i s=${_ZSH_HIGHLIGHT_GRADIENT_SPANS[j]}
    local -i e=${_ZSH_HIGHLIGHT_GRADIENT_SPANS[j+1]}
    (( s < min_start )) && min_start=$s
    (( e > max_end )) && max_end=$e
  done
  if (( max_end <= min_start )); then
    return
  fi
  for (( i = min_start; i < max_end; i++ )); do
    if [[ -n ${_zsh_highlight_gradient_paint_mask[$i]:-} ]]; then
      paint_positions+=( $i )
    fi
  done
  local -i N=${#paint_positions}
  (( N <= 0 )) && return

  local -i k pos
  for (( k = 1; k <= N; k++ )); do
    pos=${paint_positions[k]}
    local color=$(_zsh_highlight_gradient__color_for_index $(( k - 1 )) $N)
    _zsh_highlight_gradient__emit_char $pos "$color"
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

