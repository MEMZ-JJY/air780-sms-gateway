const { JSDOM, VirtualConsole } = require('jsdom');
const errs = [], warns = [];
const vc = new VirtualConsole();
vc.on('jsdomError', e => errs.push('jsdomError: ' + String(e.message).split('\n')[0]));
vc.on('error', (...a) => errs.push('console.error: ' + a.map(String).join(' ').slice(0, 200)));
vc.on('warn', (...a) => warns.push(a.map(String).join(' ').slice(0, 160)));

JSDOM.fromURL('http://127.0.0.1:8788/index.html?demo=1', {
  runScripts: 'dangerously',
  resources: 'usable',
  pretendToBeVisual: true,
  virtualConsole: vc,
  beforeParse(w) {
    
    w.ResizeObserver = w.ResizeObserver || class { observe(){} unobserve(){} disconnect(){} };
    w.IntersectionObserver = w.IntersectionObserver || class { observe(){} unobserve(){} disconnect(){} takeRecords(){return []} };
    if (!w.Element.prototype.getAnimations) w.Element.prototype.getAnimations = function(){ return []; };
    if (!w.Element.prototype.animate) w.Element.prototype.animate = function(){
      
      const an = new w.EventTarget();
      an.finished = Promise.resolve();
      an.cancel = function(){}; an.finish = function(){}; an.play = function(){};
      return an;
    };
    w.fetch = async () => ({
      ok: true, status: 200,
      text: async () => JSON.stringify({ ok: true, items: [], outbox: [] }),
      clone() { return this; }
    });
  }
}).then(dom => {
  setTimeout(() => {
    const W = dom.window, D = W.document;
    const log = (k, v) => console.log(String(k).padEnd(24) + ' ' + v);
    const click = el => el && el.dispatchEvent(new W.MouseEvent('click', { bubbles: true }));

    console.log('=== 0. 页面错误（提前抓取）===');
    console.log(errs.length ? errs.slice(0,5).join('\n').slice(0,900) : '（无）');
    console.log('\n=== 1. MDUI 加载 ===');
    log('window.mdui', typeof W.mdui);
    const tags = ['mdui-button','mdui-button-icon','mdui-fab','mdui-icon','mdui-card','mdui-list','mdui-list-item',
                  'mdui-chip','mdui-chip-set','mdui-text-field','mdui-menu','mdui-menu-item','mdui-dialog',
                  'mdui-snackbar','mdui-navigation-drawer','mdui-select','mdui-switch','mdui-top-app-bar',
                  'mdui-top-app-bar-title','mdui-divider','mdui-dropdown','mdui-tooltip'];
    log('组件已注册', tags.filter(t => W.customElements.get(t)).length + '/' + tags.length);

    console.log('\n=== 2. 关键元素 ===');
    const miss = ['btnNav','btnSearch','btnTheme','btnMore','menuMore','ddMore','threadList','msgs',
                  'drawer','swAuto','selInt','selTheme','dlgToken','dlgConfirm','dlgNew','sb','dbgBadge',
                  'tfSearch','tfNewNum','tfNewBody','tfBody','btnSend','btnAttach','btnEmoji',
                  'btnCmd','btnBack','btnExportThread','btnDelThread','btnCompose','dtAvatar','dtTitle']
                  .filter(id => !D.getElementById(id));
    log('缺失元素', miss.length ? miss.join(',') : '无');

    console.log('\n=== 3. demo 渲染（Google Messages 版式）===');
    const items = D.querySelectorAll('#threadList .conv');
    log('会话行数', items.length);
    log('首行号码块', items[0] ? items[0].querySelector('.av').textContent : '-');
    log('首行名字', items[0] ? items[0].querySelector('.cv-name').textContent : '-');
    log('首行时间', items[0] ? items[0].querySelector('.cv-time').textContent : '-');
    log('首行预览', items[0] ? items[0].querySelector('.cv-pv').textContent.slice(0, 26) : '-');
    log('列表标题', D.getElementById('appTitle').textContent);
    log('列表态隐藏输入条', D.body.classList.contains('no-compose'));

    console.log('\n=== 4. 交互（不得新开页面） ===');
    let newWin = false;
    W.open = () => { newWin = true; return {}; };
    click(items[0]);
    log('进会话 on-thread', D.body.classList.contains('on-thread'));
    log('聊天区标题', D.getElementById('dtTitle').textContent);
    log('会话头像文字', D.getElementById('dtAvatar').textContent);
    log('进会话后显示输入条', !D.body.classList.contains('no-compose'));
    log('气泡数', D.querySelectorAll('#msgs .bubble').length);
    log('  in / out', D.querySelectorAll('#msgs .bubble.in').length + ' / ' + D.querySelectorAll('#msgs .bubble.out').length);
    log('日期分隔', D.querySelectorAll('#msgs .day').length + ' → ' + (D.querySelector('#msgs .day')||{}).textContent);
    const tb = D.getElementById('tfBody');
    log('空输入时发送键亮起', D.getElementById('btnSend').classList.contains('on'));
    tb.value = 'hello 测试';
    tb.dispatchEvent(new W.Event('input', { bubbles: true }));
    log('有内容后发送键亮起', D.getElementById('btnSend').classList.contains('on'));
    click(D.getElementById('btnBack'));
    log('点返回后 on-thread', D.body.classList.contains('on-thread'));
    const chips = D.querySelectorAll('#chips mdui-chip');
    click(chips[1]);
    log('点「短信」筛后方数', D.querySelectorAll('#threadList .conv').length);
    click(chips[0]);
    ['btnSend','btnCmd','btnTheme','btnNav','btnMore','btnExportThread','btnDelThread','btnAttach','btnEmoji','btnCompose']
      .forEach(id => click(D.getElementById(id)));
    log('是否新开窗口', newWin ? '是（有问题！）' : '否');
    log('引用资源', [...D.querySelectorAll('link[href],script[src]')]
      .map(e => e.getAttribute('href') || e.getAttribute('src')).join('  '));

    console.log('\n=== 5. 日志层 ===');
    log('smsLog 类型', typeof W.smsLog);
    log('errors()', (W.smsLog && W.smsLog.errors().length) + ' 条');
    log('readyState', D.readyState);
    log('script 数', D.querySelectorAll('script').length);
    W.eval('setTimeout(function(){ throw new Error("故意异常") },0)');
    setTimeout(() => {
      log('抛异常后错误数', W.smsLog && W.smsLog.errors().length);
      const b = D.getElementById('dbgBadge');
      log('角标 class', b ? b.className : '-');
      log('角标文案', b ? b.textContent.trim().slice(0, 40) : '-');

      console.log('\n=== 6. 未捕获异常 ===');
      console.log(errs.length ? errs.slice(0, 8).join('\n') : '（无）');
      if (warns.length) console.log('warn 示例: ' + warns.slice(0, 2).join(' | ').slice(0, 180));
      process.exit(0);
    }, 400);
  }, 1500);
}).catch(e => { console.log('加载失败:', e.message); process.exit(1); });
