import type { Vault, VaultEntry } from "./domain";
import { parseTotp } from "./totp";

export const MAX_EXPORT_BYTES = 16 * 1024 * 1024;
type Node = { name: string; text: string; children: Node[] };

function decodeText(value: string): string {
  return value.replace(/&(?:amp|lt|gt|quot|apos);/g, (entity) => ({ "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": '"', "&apos;": "'" })[entity] as string);
}

function parseDocument(xml: string): Node {
  if (Buffer.byteLength(xml, "utf8") > MAX_EXPORT_BYTES) throw new Error("KeePass export exceeds the 16 MiB safety limit");
  if (/<!DOCTYPE|<!ENTITY/i.test(xml)) throw new Error("KeePass export contains a forbidden DTD or entity declaration");
  if (/&(?!(?:amp|lt|gt|quot|apos);)/.test(xml)) throw new Error("Unsupported XML entity reference");
  const root: Node = { name: "#document", text: "", children: [] };
  const stack = [root];
  const tokenPattern = /<[^>]+>|[^<]+/g;
  let consumed = 0;
  for (const match of xml.matchAll(tokenPattern)) {
    if (match.index !== consumed) throw new Error("Malformed KeePass XML");
    consumed += match[0].length;
    const token = match[0];
    if (token.startsWith("<?") || token.startsWith("<!--")) continue;
    if (token.startsWith("<!")) throw new Error("Unsupported KeePass XML declaration");
    if (token.startsWith("</")) {
      const name = token.slice(2, -1).trim();
      const node = stack.pop();
      if (!node || node === root || node.name !== name) throw new Error("Malformed KeePass XML nesting");
    } else if (token.startsWith("<")) {
      const selfClosing = token.endsWith("/>");
      const content = token.slice(1, selfClosing ? -2 : -1);
      const element = /^([A-Za-z][A-Za-z0-9_-]*)(?:\s+[A-Za-z_:][A-Za-z0-9_.:-]*=(?:"[^"]*"|'[^']*'))*\s*$/.exec(content);
      if (!element) throw new Error("Malformed KeePass XML element");
      const name = element[1];
      const node: Node = { name, text: "", children: [] };
      stack[stack.length - 1].children.push(node);
      if (!selfClosing) stack.push(node);
    } else {
      stack[stack.length - 1].text += decodeText(token);
    }
  }
  if (consumed !== xml.length || stack.length !== 1) throw new Error("Malformed KeePass XML");
  return root;
}

const child = (node: Node, name: string): Node | undefined => node.children.find((candidate) => candidate.name === name);
const text = (node: Node, name: string): string => child(node, name)?.text.trim() ?? "";

function fields(entry: Node): Map<string, string> {
  const result = new Map<string, string>();
  for (const stringNode of entry.children.filter((node) => node.name === "String")) {
    const key = text(stringNode, "Key");
    if (key) result.set(key, text(stringNode, "Value"));
  }
  return result;
}

export function parseKeePassXml(xml: string): Vault {
  const document = parseDocument(xml);
  const keepass = child(document, "KeePassFile");
  const root = keepass && child(keepass, "Root");
  const rootGroup = root && child(root, "Group");
  if (!keepass || !root || !rootGroup) throw new Error("Export is not a supported KeePass XML document");
  const rootUuid = text(rootGroup, "UUID");
  if (!rootUuid) throw new Error("KeePass root group has no UUID");
  const recycleUuid = text(child(keepass, "Meta") ?? { name: "Meta", text: "", children: [] }, "RecycleBinUUID");
  const entries: VaultEntry[] = [];

  const visit = (group: Node, parents: string[], excluded: boolean) => {
    const uuid = text(group, "UUID");
    const name = text(group, "Name");
    const path = [...parents, name].filter(Boolean);
    const skip = excluded || (recycleUuid !== "" && uuid === recycleUuid) || name.toLowerCase() === "recycle bin";
    if (!skip) for (const entry of group.children.filter((node) => node.name === "Entry")) {
      const entryUuid = text(entry, "UUID");
      if (!entryUuid) continue;
      const values = fields(entry);
      const rawTotp = values.get("otp") ?? values.get("TOTP") ?? values.get("TimeOtp-Secret-Base32");
      let totp;
      if (rawTotp) {
        try { totp = parseTotp(rawTotp); } catch { totp = undefined; }
      }
      entries.push({
        id: `${rootUuid}:${entryUuid}`,
        title: values.get("Title") ?? "Untitled",
        username: values.get("UserName") ?? "",
        password: values.get("Password") ?? "",
        url: values.get("URL") ?? "",
        group: path.join(" / "),
        ...(totp ? { totp } : {}),
      });
    }
    for (const nested of group.children.filter((node) => node.name === "Group")) visit(nested, path, skip);
  };
  visit(rootGroup, [], false);
  return { rootUuid, entries };
}
