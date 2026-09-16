import { readdir, readFile, stat } from "node:fs/promises";
import path from "node:path";
import process from "node:process";

const root = process.cwd();
const requestedScanRoots = process.argv.slice(2);
const defaultScanRoots = ["README.md", "docs", "repo"];
const requestedDocsRoots = (process.env.DOCS_ROOTS ?? "docs")
  .split(",")
  .map((entry) => entry.trim())
  .filter(Boolean);

async function exists(entry) {
  try {
    await stat(entry);
    return true;
  } catch {
    return false;
  }
}

const scanRoots = (requestedScanRoots.length > 0 ? requestedScanRoots : defaultScanRoots).map(
  (entry) => path.resolve(root, entry),
);
const presentScanRoots = (
  await Promise.all(scanRoots.map(async (entry) => ((await exists(entry)) ? entry : null)))
).filter(Boolean);
const documentationRoots = (
  await Promise.all(
    requestedDocsRoots.map(async (entry) => {
      const resolved = path.resolve(root, entry);
      return (await exists(resolved)) ? resolved : null;
    }),
  )
).filter(Boolean);

if (presentScanRoots.length === 0) {
  console.error("No documentation scan roots exist.");
  process.exit(1);
}

async function markdownFiles(entry) {
  const entryStat = await stat(entry);
  if (entryStat.isFile()) return entry.endsWith(".md") ? [entry] : [];

  const children = await readdir(entry, { withFileTypes: true });
  const nested = await Promise.all(
    children
      .filter((child) => !child.name.startsWith("."))
      .map((child) => markdownFiles(path.join(entry, child.name))),
  );
  return nested.flat();
}

function proseLines(markdown) {
  const lines = markdown.split("\n");
  let fence = null;

  return lines.map((line) => {
    const marker = line.match(/^\s*(`{3,}|~{3,})/u)?.[1];
    if (marker) {
      if (fence === null) fence = marker[0];
      else if (marker[0] === fence) fence = null;
      return "";
    }
    if (fence !== null) return "";
    return line.replace(/`[^`]*`/gu, "");
  });
}

function slugify(heading) {
  return heading
    .trim()
    .toLowerCase()
    .replace(/<[^>]+>/gu, "")
    .replace(/[^\p{Letter}\p{Number}\s_-]/gu, "")
    .replace(/\s+/gu, "-");
}

function headingAnchors(lines) {
  const occurrences = new Map();
  const anchors = new Set();

  for (const line of lines) {
    const heading = line.match(/^#{1,6}\s+(.+?)\s*#*$/u)?.[1];
    if (!heading) continue;
    const base = slugify(heading);
    const occurrence = occurrences.get(base) ?? 0;
    occurrences.set(base, occurrence + 1);
    anchors.add(occurrence === 0 ? base : `${base}-${occurrence}`);
  }

  return anchors;
}

function markdownLinks(lines) {
  const links = [];
  const pattern = /!?\[[^\]]*\]\(([^)\s]+)(?:\s+["'][^"']*["'])?\)/gu;
  for (const match of lines.join("\n").matchAll(pattern)) links.push(match[1]);
  return links;
}

function display(file) {
  return path.relative(root, file) || ".";
}

function isExternal(destination) {
  return /^[a-z][a-z0-9+.-]*:/iu.test(destination) || destination.startsWith("//");
}

function isDocumentationPage(file) {
  return documentationRoots.some(
    (docsRoot) => file === docsRoot || file.startsWith(`${docsRoot}${path.sep}`),
  );
}

const files = [
  ...new Set(
    (await Promise.all(presentScanRoots.map(markdownFiles)))
      .flat()
      .map((entry) => path.resolve(entry)),
  ),
].sort();
const incoming = new Map(files.filter(isDocumentationPage).map((file) => [file, new Set()]));
const parsed = new Map();
const errors = [];

for (const file of files) {
  const markdown = await readFile(file, "utf8");
  const lines = proseLines(markdown);
  const headings = lines.map((line) => line.match(/^(#{1,6})\s+(.+?)\s*#*$/u)).filter(Boolean);
  const h1Count = headings.filter((heading) => heading[1].length === 1).length;
  if (h1Count !== 1) {
    errors.push(`${display(file)}: expected exactly one H1; found ${h1Count}`);
  }

  let previousLevel = 0;
  for (const heading of headings) {
    const level = heading[1].length;
    if (previousLevel > 0 && level > previousLevel + 1) {
      errors.push(`${display(file)}: heading level jumps from H${previousLevel} to H${level}`);
    }
    previousLevel = level;
  }

  parsed.set(file, {
    anchors: headingAnchors(lines),
    links: markdownLinks(lines),
  });
}

for (const [file, document] of parsed) {
  for (const rawDestination of document.links) {
    if (isExternal(rawDestination)) continue;

    const [rawTarget, rawFragment] = rawDestination.split("#", 2);
    const decodedTarget = decodeURIComponent(rawTarget.split("?", 1)[0]);
    let target = decodedTarget ? path.resolve(path.dirname(file), decodedTarget) : file;

    try {
      if ((await stat(target)).isDirectory()) target = path.join(target, "README.md");
    } catch {
      errors.push(`${display(file)}: missing local link target ${rawDestination}`);
      continue;
    }

    target = path.resolve(target);
    if (incoming.has(target) && target !== file) incoming.get(target).add(file);

    if (rawFragment && target.endsWith(".md")) {
      const targetDocument = parsed.get(target);
      const fragment = decodeURIComponent(rawFragment).toLowerCase();
      if (targetDocument && !targetDocument.anchors.has(fragment)) {
        errors.push(`${display(file)}: missing heading ${rawDestination}`);
      }
    }
  }
}

const orphanExclusions = new Set(
  documentationRoots.map((docsRoot) => path.join(docsRoot, "README.md")),
);
for (const [file, sources] of incoming) {
  if (sources.size === 0 && !orphanExclusions.has(file)) {
    errors.push(`${display(file)}: page is not linked from another documentation page`);
  }
}

if (errors.length > 0) {
  console.error(`Documentation check failed with ${errors.length} error(s):`);
  for (const error of errors.sort()) console.error(`- ${error}`);
  process.exit(1);
}

console.log(
  `Documentation check passed for ${files.length} Markdown files (${incoming.size} canonical docs pages).`,
);
