# Strid app icon

The iOS icon is `ios/StridApp/Assets.xcassets/AppIcon.appiconset/Strid-AppIcon.png`.
It is an opaque 1024 × 1024 PNG with square edges; iOS applies its own mask.
The app target selects AppIcon through SDK-specific settings in project.yml.
This is a flattened asset-catalog icon, not a layered Icon Composer asset.

Generated with the built-in imagegen tool, then resized to the required dimensions with sips.

## Generation prompt

Use case: logo-brand. Create a production iPhone app icon for Strid, an on-device private document redaction app. Exactly square 1024x1024 full-bleed opaque artwork, no external presentation or device mockup. Background deep near-black graphite filling every pixel edge to edge, no rounded outer corners (iOS supplies masking). Center one beautifully proportioned upright silver-white document silhouette with softly rounded corners and a subtle folded upper-right corner, occupying roughly 58% width and 66% height. Across the document, three bold near-black rounded redaction bars, staggered lengths in a purposeful rhythm; the middle bar has a restrained cool blue #3AA9FF edge highlight suggesting precision. Premium minimal industrial design, softly frosted silver surface, extremely restrained depth and soft lighting, crisp geometry, strong recognizable silhouette at tiny sizes. Straight-on orthographic view. Calm confidential trustworthy feeling. No lettering, no words, no shield, no padlock, no extra badges, no busy textures, no outer frame, no watermark. Deliver only the final square icon.

## ST / RID revision

The current icon includes ST above RID within the redaction bars. A standalone
copy is saved at `docs/brand/strid-logo.png`; the previous icon is preserved at
`docs/brand/strid-icon-original.png`.

Edited using the built-in imagegen tool with this prompt:

Edit the supplied Strid app icon. Preserve the graphite full bleed square background, centered silver folded document silhouette, premium materials, and cool blue accent. Redesign the interior as a bold typographic logo reading exactly 'ST' on the first line and 'RID' on the second line, together spelling STRID. Use large very clear uppercase heavy geometric sans serif silver-white letters inside two near-black rounded redaction bars. First bar contains ST, second wider bar contains RID with the restrained blue top-edge accent. Remove the third empty bar and rebalance the two text bars vertically within the document. Text is the dominant interior detail and must be readable at app-icon sizes. Clean optical spacing, confident compact typography. Do not add any other text or objects. Square opaque 1024x1024 artwork, no rounded outer mask, no mockup. Retain the existing design identity while making ST / RID an integral part of the logo.

[Apple app icon guidance](https://developer.apple.com/design/human-interface-guidelines/app-icons/)

## Liquid Glass style redacted R (current)

Replaced the asset-catalog icon with a glass rendition of the redacted R.
Previous artwork is preserved at `docs/brand/strid-icon-before-glass.png`.
This is a static glass-style PNG, not a layered Icon Composer asset.
Generated with the built-in imagegen tool and resized with sips to 1024 × 1024.

Generation prompt: Transform the redacted R logo into a premium Liquid Glass
style iPhone app icon for Strid. Preserve the R silhouette and horizontal censor
bar separated by narrow negative-space gaps. Use translucent frosted optical
glass with rounded bevels, polished reflections and icy silver-blue refraction.
The censor bar is darker smoked glass with a luminous fine rim. Deep midnight
navy full-bleed background with subtle blue illumination. Center the mark within
safe margins. Opaque square artwork; no external rounded tile, device mockup,
text, additional symbols or border.

## Monochrome glass revision (current)

Replaced the blue glass icon with neutral black, white, and silver artwork using
built-in imagegen. Retains the redacted R and glass finish; exported as an opaque
1024 × 1024 PNG to the same AppIcon asset path.

Edit prompt: Remove all color. Strictly monochrome neutral grayscale black,
white, silver and gray only. Preserve the redacted R silhouette, proportions,
positioning, glass material, polished reflections, smoked glass censor bar,
margins, and square full-bleed opaque composition. Change the navy background
to neutral charcoal black and blue illumination to neutral white and silver.
No blue, cyan, warm tint, chromatic aberration, text, or additional elements.
