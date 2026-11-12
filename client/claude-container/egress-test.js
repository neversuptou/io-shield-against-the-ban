const net = require('net');
const tls = require('tls');

const proxy = process.env.PROXY_IP + ':18082';
const [host, port] = ['api.ipify.org', 443];

const raw = net.connect(18082, process.env.PROXY_IP, () => {
  raw.write(
    `CONNECT ${host}:${port} HTTP/1.1\r\nHost: ${host}:${port}\r\n\r\n`
  );
});

let buf = Buffer.alloc(0);
raw.on('data', (d) => {
  buf = Buffer.concat([buf, d]);
  if (buf.includes(Buffer.from('\r\n\r\n'))) {
    const head = buf.toString('utf8');
    if (!head.startsWith('HTTP/1.1 200')) {
      console.error('CONNECT failed:\n' + head);
      process.exit(1);
    }
    raw.removeAllListeners('data');
    // Switch to TLS over the established tunnel.
    const t = tls.connect({ socket: raw, servername: host, rejectUnauthorized: true }, () => {
      t.write(`GET / HTTP/1.1\r\nHost: ${host}\r\nConnection: close\r\n\r\n`);
    });
    let body = '';
    t.on('data', (d) => (body += d));
    t.on('end', () => {
      const ip = body.split('\r\n\r\n')[1];
      console.log('EGRESS_IP=' + ip.trim());
      process.exit(0);
    });
    t.on('error', (e) => { console.error('TLS ERR', e.message); process.exit(1); });
  }
});
raw.on('error', (e) => { console.error('CONN ERR', e.message); process.exit(1); });
setTimeout(() => { console.error('TIMEOUT'); process.exit(1); }, 25000);
