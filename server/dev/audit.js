
const fs = require('fs');
const meta = require('../vendor/html-data.json').tags;
const byName = {};
meta.forEach(c => { if (c && c.name) byName[c.name] = c; });

const html = fs.readFileSync('../index.html', 'utf8');

const re = /<(mdui-[a-z-]+)((?:\s+[^\s=>"]+(?:\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+))?)*)\s*(\/?)>/gi;
/* 全文件通用、无法靠父元素判断的插槽名（dialog 的 action 按钮会被误判成 button 的插槽） */
const ANY_SLOTS = ['action'];
const KNOWN_SLOTS = {
  'mdui-top-app-bar': [],           // 无具名 slot，靠顺序
  'mdui-top-app-bar-title': [],
  'mdui-dropdown': ['trigger'],
  'mdui-menu': [],
  'mdui-menu-item': [],
  'mdui-list': [],
  'mdui-list-item': ['start', 'end', 'icon', 'end-icon'],
  'mdui-text-field': ['label', 'end', 'start', 'helper-text'],
  'mdui-chip-set': [],
  'mdui-chip': ['start', 'end', 'icon', 'delete-icon'],
  'mdui-dialog': ['action'],   /* dialog 的按钮插槽就叫 action，会被误判成 button 的 */
  'mdui-navigation-drawer': ['header', 'footer'],
  'mdui-button': ['start', 'end'],
  'mdui-button-icon': [],
  'mdui-fab': [],
  'mdui-icon': [],
  'mdui-switch': ['start', 'end'],
  'mdui-select': ['label', 'helper-text'],
  'mdui-snackbar': [],
  'mdui-divider': [],
};

/* html-data.json 快照里没有、但 MDUI 确实存在的组件，单独放行 */
const EXTRA_TAGS = ['mdui-chip-set'];

let m, n = 0, bad = 0;
const lines = [];
while ((m = re.exec(html))) {
  const tag = m[1].toLowerCase();
  const attrsStr = m[2] || '';
  n++;
  const info = byName[tag];
  if (!info) {
    if (EXTRA_TAGS.indexOf(tag) < 0) { lines.push(`${tag}: 组件不在官方元数据里（可能已改名）`); bad++; }
    continue;
  }
  const official = info.attributes.map(a => a.name);
  const reAttr = /([^\s=]+)(?:\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+))?/g;
  let a2;
  while ((a2 = reAttr.exec(attrsStr))) {
    const an = a2[1];
    if (!an || an === '/') continue;
    
    if (['id', 'class', 'style', 'slot', 'hidden', 'lang', 'title'].indexOf(an) >= 0) continue;
    if (official.indexOf(an) < 0) {
      lines.push(`${tag} 上的 "${an}" 不是官方属性（官方只有: ${official.join(',')}）`);
      bad++;
    }
  }
}

const stack = [];
const openTags = /<(mdui-[a-z-]+)((?:\s+[^\s=>"]+(?:\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+))?)*)\s*(\/?)>/gi;
let t;
while ((t = openTags.exec(html))) {
  const idx = t.index;
  if (t[3] === '/') continue;                 // 自闭合不入栈
  stack.push({ tag: t[1], idx: idx, len: t[0].length });
}
const slotRe = /<mdui-[a-z-]+[^>]*\sslot="([^"]+)"/gi;
const consumed = [];
let s;
while ((s = slotRe.exec(html))) {
  const at = s.index;
  /* 找到最靠近 yet 仍在 slot 元素之前打开的祖先 */
  let parent = null;
  for (let i = stack.length - 1; i >= 0; i--) {
    if (stack[i].idx < at && consumed.indexOf(i) < 0) { parent = stack[i]; consumed.push(i); break; }
  }
  if (!parent) continue;
  const sn = s[1];
  const ok = KNOWN_SLOTS[parent.tag];
  if (ANY_SLOTS.indexOf(sn) >= 0) continue;
  if (ok && ok.indexOf(sn) < 0) {
    lines.push(`<${parent.tag}> 内 <mdui-*> 的 slot="${sn}" 不是官方插槽（该组件插槽: ${ok.join(',') || '无'}）`);
    bad++;
  }
}

console.log(`扫描 mdui 元素 ${n} 个，异常 ${bad} 处`);
if (lines.length) console.log(lines.join('\n'));
else console.log('未发现非法属性/插槽');
