# Selectable layouts

These are decision templates, not mandatory skeletons. Omit roles that do not have meaningful content.

## Single-project layout

Use when one main product/system has a coherent authority model and roadmap.

```text
README.md
AGENTS.md
docs/
├── README.md
├── STYLE.md                 # optional when rules are substantial
├── PRODUCT.md               # optional for product repositories
├── GLOSSARY.md              # optional when terminology needs an authority
├── architecture/
│   └── README.md
├── specification/           # optional
│   └── README.md
├── protocols/               # optional
│   └── README.md
├── reference/               # optional
│   └── README.md
├── developer/               # optional
│   └── README.md
└── roadmap/
    ├── README.md
    └── initiatives/         # optional
        └── README.md
repo/                        # independently optional
└── README.md
```

A compact system may combine closely related subjects into a few architecture pages. Do not create empty `specification/`, `protocols/`, or `reference/` areas just to match the diagram.

## Multi-project layout

Use when several major projects require distinct contracts, audiences, terminology, or roadmaps.

```text
README.md
AGENTS.md
docs/
├── README.md                # repo-wide reader router
├── STYLE.md                 # shared editorial and authority rules
├── shared/                  # optional; only genuinely shared product concepts
│   └── README.md
├── project-a/
│   ├── README.md
│   ├── architecture/
│   ├── specification/
│   ├── protocols/
│   ├── reference/
│   ├── developer/
│   └── roadmap/
└── project-b/
    ├── README.md
    └── ...only needed roles
repo/                        # independently optional, repo-wide only
└── README.md
```

A project may use a separate developer-docs tree when that audience is large enough to need its own reading path. Otherwise keep developer guides under the project.

Do not interpret packages, applications, or deployables as documentation projects automatically. A project boundary is justified by independent reader entry points or semantic authorities.

## Selecting `repo/`

Create a separate `repo/` area when several substantial topics exist, such as:

- repository layout and placement rules;
- workspace/package-manager responsibilities;
- tooling, formatting, linting, and testing;
- CI generation and runner boundaries;
- infrastructure and release engineering;
- application framework conventions.

Keep these in root contributor guidance when they are short. `repo/` describes current engineering conventions; it does not own product behavior or delivery state.

## Hybrid cases

A monorepo can still use the single-project layout when many packages implement one system. A mostly single-product repo can use the multi-project layout if it also contains an independently consumed SDK or protocol with a distinct audience and lifecycle. Decide from authority and readership, not repository size.
