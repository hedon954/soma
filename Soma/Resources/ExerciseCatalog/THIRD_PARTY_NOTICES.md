# Exercise Catalog Asset Notices

## Free Exercise DB action images

- Source: https://github.com/yuhonas/free-exercise-db
- Upstream license: The Unlicense (public domain dedication)
- Included files: `Action/free_*.jpg`
- Local use: bundled, silent exercise illustrations that are associated only after
  a user-created `ExerciseDefinition` matches the corresponding standard action.

The upstream collection contains action photographs from the public-domain
Free Exercise DB dataset. Soma does not treat the upstream catalog as user data
and does not expose unused catalog entries through the exercise library or Agent
tools.

## Soma generated illustrations

Files prefixed with `soma_` were generated for Soma as project-bound assets.
They are used as action illustrations and generic fallbacks. Static
`soma_muscle_*.png` maps are legacy bundled assets retained for fill-only
activation of older installs; the product UI now prefers programmatic muscle
maps.

## react-native-body-highlighter muscle SVG paths

- Source: https://github.com/HichamELBSI/react-native-body-highlighter
  (same SVG body assets redistributed by
  https://github.com/soroojshehryar/react-muscle-highlighter)
- Upstream license: MIT (see `REACT_NATIVE_BODY_HIGHLIGHTER_LICENSE.txt`)
- Included use: SVG path `d` strings adapted into `MuscleMapPathData.swift` for
  offline anterior/posterior muscle highlighting with leader labels
- Related lineage: earlier Soma builds used polygon points from
  `body-highlighter` / `react-body-highlighter` (MIT, see
  `BODY_HIGHLIGHTER_LICENSE.txt`); that polygon dataset is no longer shipped.

Soma does not embed the JavaScript or React Native runtime. Only the geometric
path data and license notices are redistributed.
