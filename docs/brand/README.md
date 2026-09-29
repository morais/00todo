# 00Todo brand

00Todo is a sibling of 00Widget. It keeps the two-card agent, white fedora,
slashed-zero eyes, electric-blue edge, and teal accent. Its chart-shaped mouth
is replaced by three checked task rows, and its icon has a violet gradient
instead of 00Widget's deep navy so the apps are easy to tell apart. The wordmark uses
the same blue `00`, navy/white name, and Avenir Next styling, now reading
`00Todo` exactly.

![00Todo brand preview](brand-preview.png)

`sources/` contains Pedro Morais's approved 00Widget master artwork and its
original license. The source is included so the derived 00Todo assets are
reproducible; it is not a general-purpose permission to reuse 00Widget art.
The 00Todo assets have their own [license](LICENSE), separate from the code.

Regenerate from the repository root with Python 3.10+ and Pillow 11.3.0:

```sh
python3 -m pip install -r docs/brand/requirements.txt
python3 docs/brand/generate.py
```

The generator updates the iOS app icon, in-app mark and light/dark wordmarks,
as well as these brand exports:

| Asset | Use |
| --- | --- |
| `mark-1024.png` | Opaque app/plugin icon |
| `mark-transparent-1024.png` | Mark on a suitable dark surface |
| `wordmark-horizontal.png` | Light-surface lockup |
| `wordmark-horizontal-transparent-light.png` | Transparent light-surface lockup |
| `wordmark-horizontal-transparent.png` | Transparent dark-surface lockup |
| `brand-preview.png` | Identity overview |

Use `00Todo` in user-visible text. Keep `com.00todo.app`, `api.00todo.com`,
and other already registered technical identifiers lower-case; changing their
case or spelling would break distribution and authentication.
