/// CDN 分片签名参数。
///
/// 服务端 voldn-ser01.51touxiang.com 对不带这组参数的 m3u8/分片请求会把
/// 单连接限速到约 950 B/s（等于不可播）。这组值来自安卓 App 播放器内部
/// 生成的播放地址，实测不校验时效、可跨剧集复用。
const String hjSegmentAuth =
    'pid=asMIz%2F%2BMYjq3wkFkBCOzjQKJ34A%2BzuHL048plsLVICs%3D'
    '&utk=u_n73W7h7QsYsFVe8Mwc74'
    '&uk=Vm3A4Js0SB79NbMZ0vFJ5oJOiIxJx0mzT6QQ9kr3wK0%3D'
    '&spl=213&t=1792584307&sign=a4ffd966caae80e00d3f3c508395d6f6'
    '&ip=119.182.109.199';

const String hjCdnHost = 'https://voldn-ser01.51touxiang.com';
