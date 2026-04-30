#!/usr/bin/env python3
"""
解析 llm_proxy_requests.log，提取流式 SSE 响应并拼接成完整响应内容。

日志格式：
    -------------------- 2026-04-30 17:50:32 --------------------
    [REQUEST] POST /v1/chat/completions
    [Model] deepseek-v4-flash
    [Forward To] https://api.deepseek.com/v1/chat/completions
    [Duration] 2247ms
    [Status] 200
    [Request Body]
    { ... JSON ... }
    [Response Body]
    data: {"id":"...","object":"chat.completion.chunk",...,"delta":{"content":"你好"}...}
    data: {"id":"...","object":"chat.completion.chunk",...,"delta":{"content":"！"}...}
    ...
    data: [DONE]

用法：
    python3 parse_logs.py [日志文件路径]             # 解析日志并输出到终端
    python3 parse_logs.py -o output.txt             # 输出到文件
    python3 parse_logs.py --no-body                 # 只显示请求摘要
    python3 parse_logs.py -n 2                      # 只显示最近 N 个请求
"""

import re
import sys
import json
import argparse


SEPARATOR_RE = re.compile(r'^-{20} (\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) -{20}$')
REQUEST_RE = re.compile(r'^\[REQUEST\] (.+)$')
MODEL_RE = re.compile(r'^\[Model\] (.+)$')
FORWARD_RE = re.compile(r'^\[Forward To\] (.+)$')
DURATION_RE = re.compile(r'^\[Duration\] (.+)$')
STATUS_RE = re.compile(r'^\[Status\] (\d+)$')
REQUEST_BODY_RE = re.compile(r'^\[Request Body\]$')
RESPONSE_BODY_RE = re.compile(r'^\[Response Body\]$')
ERROR_RE = re.compile(r'^\[Error\] (.+)$')
STREAM_DATA_RE = re.compile(r'^data: (.+)$')
STREAM_DONE_RE = re.compile(r'^data: \[DONE\]$')


def reconstruct_stream_response(chunks):
    """
    将一系列 SSE chunk JSON 拼接成完整响应文本。
    对 chat.completion.chunk 类型，提取所有 delta.content 拼接。
    """
    contents = []
    usage_data = {}
    for chunk_str in chunks:
        try:
            data = json.loads(chunk_str)
        except json.JSONDecodeError:
            continue

        obj_type = data.get('object', '')
        if obj_type == 'chat.completion.chunk':
            choices = data.get('choices', [])
            for choice in choices:
                delta = choice.get('delta', {})
                content = delta.get('content', '')
                if content:
                    contents.append(content)
            if data.get('usage'):
                usage_data = data['usage']
        else:
            # 非标准 chunk 类型，直接返回原始 JSON 组
            return '\n'.join(chunks)

    full_text = ''.join(contents)
    if not full_text and not usage_data:
        return json.dumps(chunks, ensure_ascii=False, indent=2)

    result = full_text
    if usage_data:
        usage_str = json.dumps(usage_data, ensure_ascii=False)
        result += f'\n\n--- Usage: {usage_str} ---'
    return result


def parse_log(filepath):
    """
    解析日志文件，返回请求记录列表。
    状态机: INIT -> HEADER -> REQUEST_BODY -> RESPONSE_BODY
    """
    with open(filepath, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    records = []
    current = None
    section = 'HEADER'  # HEADER | REQUEST_BODY | RESPONSE_BODY
    stream_chunks = []

    def flush_current():
        """将当前请求归档并重置"""
        nonlocal current, section, stream_chunks
        if current is None:
            return
        if section == 'RESPONSE_BODY' and stream_chunks:
            current['response_body'] = reconstruct_stream_response(stream_chunks)
            current['is_stream'] = True
        current.setdefault('request_body', '')
        current.setdefault('response_body', '')
        current.setdefault('is_stream', False)
        records.append(current)
        current = None
        section = 'HEADER'
        stream_chunks = []

    for raw_line in lines:
        line = raw_line.rstrip('\n')
        if not line:
            # 空行在请求体/RESPONSE_BODY 中忽略，在 HEADER 中忽略
            continue

        # 分隔线 → 新请求开始
        sep_match = SEPARATOR_RE.match(line)
        if sep_match:
            flush_current()
            current = {
                'time_str': sep_match.group(1),
                'method': '',
                'path': '',
                'model': '',
                'forward_to': '',
                'duration': '',
                'status_code': '',
                'request_body': None,
                'response_body': None,
                'error': '',
                'is_stream': False,
            }
            section = 'HEADER'
            continue

        if current is None:
            continue

        # ---- HEADER 阶段 ----
        if section == 'HEADER':
            req_match = REQUEST_RE.match(line)
            if req_match:
                parts = req_match.group(1).split(' ', 1)
                current['method'] = parts[0]
                current['path'] = parts[1] if len(parts) > 1 else ''
                continue

            model_match = MODEL_RE.match(line)
            if model_match:
                current['model'] = model_match.group(1)
                continue

            forward_match = FORWARD_RE.match(line)
            if forward_match:
                current['forward_to'] = forward_match.group(1)
                continue

            duration_match = DURATION_RE.match(line)
            if duration_match:
                current['duration'] = duration_match.group(1)
                continue

            status_match = STATUS_RE.match(line)
            if status_match:
                current['status_code'] = status_match.group(1)
                continue

            if REQUEST_BODY_RE.match(line):
                section = 'REQUEST_BODY'
                current['request_body'] = ''
                continue

            if RESPONSE_BODY_RE.match(line):
                # 没有请求体，直接进了响应体
                section = 'RESPONSE_BODY'
                current['request_body'] = ''
                continue

            if ERROR_RE.match(line):
                current['error'] = ERROR_RE.match(line).group(1)
                continue

            # HEADER 阶段不识别的行，忽略
            continue

        # ---- REQUEST_BODY 阶段 ----
        if section == 'REQUEST_BODY':
            if REQUEST_BODY_RE.match(line):
                # 行内容就是 [Request Body]，忽略（已经进入这个 section 了）
                continue
            if RESPONSE_BODY_RE.match(line):
                section = 'RESPONSE_BODY'
                continue
            if ERROR_RE.match(line):
                current['error'] = ERROR_RE.match(line).group(1)
                section = 'HEADER'
                continue

            # 请求体内容
            if current['request_body']:
                current['request_body'] += '\n' + line
            else:
                current['request_body'] = line
            continue

        # ---- RESPONSE_BODY 阶段 ----
        if section == 'RESPONSE_BODY':
            if ERROR_RE.match(line):
                # 错误在响应体之后
                if stream_chunks:
                    current['response_body'] = reconstruct_stream_response(stream_chunks)
                    current['is_stream'] = True
                    stream_chunks = []
                current['error'] = ERROR_RE.match(line).group(1)
                section = 'HEADER'
                continue

            done_match = STREAM_DONE_RE.match(line)
            if done_match:
                # 流结束
                current['response_body'] = reconstruct_stream_response(stream_chunks)
                current['is_stream'] = True
                stream_chunks = []
                section = 'HEADER'
                continue

            data_match = STREAM_DATA_RE.match(line)
            if data_match:
                # SSE data: 行
                stream_chunks.append(data_match.group(1))
                continue

            # 非 data: 行 -> 非流式响应体（可能是 JSON 或其他）
            # 但也可能是 data: 在多行间被截断？不处理这种极端情况
            if current['response_body']:
                current['response_body'] += '\n' + line
            else:
                current['response_body'] = line
            continue

    # 最终归档
    flush_current()
    return records


def format_duration(raw):
    """清理 duration 字符串"""
    return raw.replace('Duration: ', '').strip() if raw else ''


def pretty_print_records(records, args):
    """美化输出记录"""
    for i, rec in enumerate(records):
        print(f"{'='*60}")
        print(f"请求 #{i+1}  |  {rec['time_str']}")
        print(f"{'─'*60}")
        print(f"  方法    : {rec['method']}")
        print(f"  路径    : {rec['path']}")
        print(f"  模型    : {rec['model']}")
        if rec['forward_to']:
            print(f"  转发至  : {rec['forward_to']}")
        print(f"  状态码  : {rec['status_code']}  |  耗时: {rec['duration']}")
        if rec['error']:
            print(f"  错误    : {rec['error']}")

        # 请求体
        body_type_label = '流式请求' if rec.get('is_stream_request') else '非流式'
        if rec['request_body'] and not args.no_body:
            print(f"\n  ╭─ Request Body ({body_type_label}) " + '─'*35)
            try:
                parsed = json.loads(rec['request_body'])
                for line in json.dumps(parsed, ensure_ascii=False, indent=2).split('\n'):
                    print(f"  │ {line}")
            except (json.JSONDecodeError, TypeError):
                for line in rec['request_body'].split('\n'):
                    print(f"  │ {line}")
            print(f"  ╰{'─'*55}")

        # 响应体
        if rec['response_body'] and not args.no_body:
            resp_label = '流式响应 (已拼接)' if rec['is_stream'] else '非流式响应'
            print(f"\n  ╭─ Response Body ({resp_label}) " + '─'*28)
            print(f"  │ {rec['response_body']}")
            print(f"  ╰{'─'*55}")
        print()

    print(f"{'='*60}")
    print(f"共 {len(records)} 个请求")


def json_output(records, args):
    """以 JSON 数组格式输出"""
    output = []
    for rec in records:
        entry = {
            'time': rec['time_str'],
            'method': rec['method'],
            'path': rec['path'],
            'model': rec['model'],
            'forward_to': rec.get('forward_to', ''),
            'duration': rec.get('duration', ''),
            'status_code': rec.get('status_code', ''),
            'error': rec.get('error', ''),
            'is_stream': rec.get('is_stream', False),
        }
        if not args.no_body:
            entry['request_body'] = rec.get('request_body', '')
            entry['response_body'] = rec.get('response_body', '')
        output.append(entry)
    print(json.dumps(output, ensure_ascii=False, indent=2))


def main():
    parser = argparse.ArgumentParser(
        description='解析 llm_proxy_requests.log，拼接流式响应',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument('log_file', nargs='?',
                        default='/Volumes/Development/llm_proxy/llm_proxy/llm_proxy_requests.log',
                        help='日志文件路径（默认: llm_proxy_requests.log）')
    parser.add_argument('-o', '--output', help='输出到文件')
    parser.add_argument('--no-body', action='store_true', help='不显示请求/响应体')
    parser.add_argument('-n', '--last', type=int, default=0,
                        help='只显示最近 N 个请求（0=全部）')
    parser.add_argument('--json', action='store_true', help='以 JSON 格式输出')
    parser.add_argument('--no-color', action='store_true', help='不输出 ANSI 颜色')
    args = parser.parse_args()

    records = parse_log(args.log_file)

    if args.last > 0:
        records = records[-args.last:]

    out_func = json_output if args.json else pretty_print_records

    if args.output:
        with open(args.output, 'w', encoding='utf-8') as f:
            old_stdout = sys.stdout
            sys.stdout = f
            out_func(records, args)
            sys.stdout = old_stdout
        print(f'结果已输出到: {args.output}')
    else:
        out_func(records, args)


if __name__ == '__main__':
    main()
