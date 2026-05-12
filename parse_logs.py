#!/usr/bin/env python3
"""
解析 llm_proxy 请求日志，生成结构化 JSON 数据。
支持 Anthropic 和 OpenAI 的 SSE 流式响应拼接。

用法: python parse_logs.py <日志文件路径> [-o 输出文件路径]
"""

import re
import json
import sys
import argparse
from datetime import datetime


# ==================== 日志分割 ====================

# 匹配日志条目分隔线: -------------------- 2026-05-01 10:14:53 --------------------
SEPARATOR_RE = re.compile(r'^-{20}\s+(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})\s+-{20}$')

# 匹配元数据行
META_PATTERNS = {
    'request':    re.compile(r'^\[REQUEST\]\s+(\S+)\s+(.+)$'),
    'model':      re.compile(r'^\[Model\]\s+(.+)$'),
    'forward_to': re.compile(r'^\[Forward To\]\s+(.+)$'),
    'duration':   re.compile(r'^\[Duration\]\s+(\d+)ms$'),
    'first_byte': re.compile(r'^\[First Byte\]\s+(\d+)ms$'),
    'status':     re.compile(r'^\[Status\]\s+(\d+)$'),
}


def split_log_entries(filepath: str) -> list[dict]:
    """将日志文件按分隔线切分为独立条目"""
    entries = []
    current_lines = []
    current_time = None

    with open(filepath, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.rstrip('\n')
            m = SEPARATOR_RE.match(line)
            if m:
                # 遇到新分隔线，保存上一条
                if current_time and current_lines:
                    entries.append({'timestamp': current_time, 'lines': current_lines})
                current_time = m.group(1)
                current_lines = []
            else:
                current_lines.append(line)

    # 最后一条
    if current_time and current_lines:
        entries.append({'timestamp': current_time, 'lines': current_lines})

    return entries


# ==================== 元数据解析 ====================

def parse_metadata(lines: list[str]) -> tuple[dict, int]:
    """
    解析元数据行，返回 (metadata_dict, body_start_index)。
    body_start_index 指向 [Request Body] 之后的第一行。
    """
    meta = {}
    idx = 0
    while idx < len(lines):
        line = lines[idx]

        # 遇到 [Request Body] 标记，后续为请求体
        if line.strip() == '[Request Body]':
            idx += 1
            break

        for key, pattern in META_PATTERNS.items():
            m = pattern.match(line)
            if m:
                if key == 'request':
                    meta['method'] = m.group(1)
                    meta['path'] = m.group(2)
                elif key == 'duration':
                    meta['duration_ms'] = int(m.group(1))
                elif key == 'first_byte':
                    meta['first_byte_ms'] = int(m.group(1))
                elif key == 'status':
                    meta['status_code'] = int(m.group(1))
                else:
                    meta[key] = m.group(1)
                break
        idx += 1

    return meta, idx


# ==================== 请求体 / 响应体分割 ====================

def split_request_response(lines: list[str], body_start: int) -> tuple[str, str]:
    """
    从 body_start 开始，找到 [Response Body] 分界，
    返回 (request_body_str, response_body_str)。
    """
    response_marker = None
    for i in range(body_start, len(lines)):
        if lines[i].strip() == '[Response Body]':
            response_marker = i
            break

    if response_marker is not None:
        req_body = '\n'.join(lines[body_start:response_marker])
        resp_body = '\n'.join(lines[response_marker + 1:])
    else:
        req_body = '\n'.join(lines[body_start:])
        resp_body = ''

    return req_body.strip(), resp_body.strip()


# ==================== 请求体解析 ====================

def parse_request_body(raw: str) -> dict | None:
    """解析请求体 JSON，提取关键字段"""
    if not raw:
        return None
    try:
        body = json.loads(raw)
    except json.JSONDecodeError:
        return {'raw': raw}

    result = {}
    # 提取模型
    if 'model' in body:
        result['model'] = body['model']

    # 提取 stream 标志
    if 'stream' in body:
        result['stream'] = body['stream']

    # 提取消息（简化：只保留 role 和 text 内容摘要）
    if 'messages' in body:
        result['messages'] = _simplify_messages(body['messages'])

    # 保留其他顶层参数（排除 messages 和已提取的）
    extras = {k: v for k, v in body.items() if k not in ('model', 'stream', 'messages')}
    if extras:
        result['other_params'] = extras

    return result


def _simplify_messages(messages: list) -> list[dict]:
    """简化消息列表，提取 role 和文本内容摘要"""
    simplified = []
    for msg in messages:
        role = msg.get('role', 'unknown')
        content = msg.get('content', '')

        # content 可能是字符串或数组
        if isinstance(content, str):
            text = content
        elif isinstance(content, list):
            # 拼接所有 text 类型的内容
            parts = []
            tool_uses = []
            tool_results = []
            for item in content:
                if isinstance(item, dict):
                    t = item.get('type', '')
                    if t == 'text':
                        parts.append(item.get('text', ''))
                    elif t == 'tool_use':
                        tool_uses.append({
                            'name': item.get('name', ''),
                            'id': item.get('id', ''),
                            'input_preview': _truncate(json.dumps(item.get('input', {}), ensure_ascii=False), 200),
                        })
                    elif t == 'tool_result':
                        tool_results.append({
                            'tool_use_id': item.get('tool_use_id', ''),
                            'content_preview': _truncate(
                                item.get('content', '') if isinstance(item.get('content'), str)
                                else json.dumps(item.get('content', ''), ensure_ascii=False),
                                200
                            ),
                        })
                    elif t == 'image':
                        parts.append('[image]')
            text = '\n'.join(parts)
            entry = {'role': role, 'text': _truncate(text, 500)}
            if tool_uses:
                entry['tool_uses'] = tool_uses
            if tool_results:
                entry['tool_results'] = tool_results
            simplified.append(entry)
            continue
        else:
            text = str(content)

        simplified.append({'role': role, 'text': _truncate(text, 500)})

    return simplified


def _truncate(s: str, max_len: int) -> str:
    if len(s) <= max_len:
        return s
    return s[:max_len] + f'... ({len(s)} chars total)'


# ==================== SSE 响应解析 ====================

def parse_sse_response(raw: str, endpoint_path: str = '') -> dict:
    """
    解析 SSE 响应，自动检测 Anthropic 或 OpenAI 格式。
    返回结构化的响应数据。
    """
    if not raw:
        return {'type': 'empty'}

    # 非 SSE：尝试直接解析为 JSON（非流式响应）
    if not raw.startswith('event:') and not raw.startswith('data:'):
        try:
            return {'type': 'json', 'data': json.loads(raw)}
        except json.JSONDecodeError:
            return {'type': 'raw', 'data': raw[:1000]}

    # 解析 SSE 事件流
    events = _parse_sse_events(raw)

    if not events:
        return {'type': 'raw', 'data': raw[:1000]}

    # 根据第一个事件判断格式
    first_data = events[0].get('data', {})
    if isinstance(first_data, dict):
        msg_type = first_data.get('type', '')
        # Anthropic 格式: type 字段为 message_start / content_block_start 等
        if msg_type in ('message_start', 'ping') or 'message' in first_data:
            return _assemble_anthropic_sse(events)

    # OpenAI 格式: choices[].delta
    if isinstance(first_data, dict) and 'choices' in first_data:
        return _assemble_openai_sse(events)

    # 兜底：尝试两种格式
    if endpoint_path.endswith('/v1/messages'):
        return _assemble_anthropic_sse(events)
    elif endpoint_path.endswith('/v1/chat/completions'):
        return _assemble_openai_sse(events)

    return _assemble_anthropic_sse(events)


def _parse_sse_events(raw: str) -> list[dict]:
    """将 SSE 文本解析为事件列表 [{event, data}, ...]"""
    events = []
    current_event = None
    current_data_lines = []

    for line in raw.split('\n'):
        line = line.rstrip()

        if line.startswith('event:'):
            # 保存上一个事件
            if current_data_lines:
                events.append(_build_event(current_event, '\n'.join(current_data_lines)))
                current_data_lines = []
            current_event = line[len('event:'):].strip()

        elif line.startswith('data:'):
            data_str = line[len('data:'):].strip()
            current_data_lines.append(data_str)

        elif line == '' and current_data_lines:
            # 空行表示事件结束
            events.append(_build_event(current_event, '\n'.join(current_data_lines)))
            current_event = None
            current_data_lines = []

    # 处理末尾
    if current_data_lines:
        events.append(_build_event(current_event, '\n'.join(current_data_lines)))

    return events


def _build_event(event_type: str | None, data_str: str) -> dict:
    """构建单个 SSE 事件"""
    result = {}
    if event_type:
        result['event'] = event_type

    # 尝试解析 data 为 JSON
    try:
        result['data'] = json.loads(data_str)
    except (json.JSONDecodeError, TypeError):
        if data_str == '[DONE]':
            result['data'] = '[DONE]'
        else:
            result['data'] = data_str

    return result


# ==================== Anthropic SSE 拼接 ====================

def _assemble_anthropic_sse(events: list[dict]) -> dict:
    """
    拼接 Anthropic SSE 流为完整响应。
    处理 text_delta（文本）和 input_json_delta（工具调用参数）。
    """
    result = {
        'type': 'anthropic_sse',
        'model': None,
        'stop_reason': None,
        'usage': None,
        'content': [],  # 最终拼接的 content blocks
    }

    # 临时存储：按 index 收集 content blocks
    blocks = {}  # index -> {type, text/name/id/input}

    for evt in events:
        data = evt.get('data', {})
        if not isinstance(data, dict):
            continue

        evt_type = data.get('type', '')

        if evt_type == 'message_start':
            msg = data.get('message', {})
            result['model'] = msg.get('model')
            result['usage'] = msg.get('usage')
            result['id'] = msg.get('id')

        elif evt_type == 'content_block_start':
            idx = data.get('index', 0)
            block = data.get('content_block', {})
            block_type = block.get('type', 'text')
            if block_type == 'text':
                blocks[idx] = {'type': 'text', 'text': block.get('text', '')}
            elif block_type == 'tool_use':
                blocks[idx] = {
                    'type': 'tool_use',
                    'id': block.get('id', ''),
                    'name': block.get('name', ''),
                    'input_json': '',
                }
            elif block_type == 'thinking':
                blocks[idx] = {'type': 'thinking', 'thinking': block.get('thinking', '')}

        elif evt_type == 'content_block_delta':
            idx = data.get('index', 0)
            delta = data.get('delta', {})
            delta_type = delta.get('type', '')

            if idx not in blocks:
                blocks[idx] = {'type': 'text', 'text': ''}

            if delta_type == 'text_delta':
                blocks[idx].setdefault('text', '')
                blocks[idx]['text'] += delta.get('text', '')
            elif delta_type == 'input_json_delta':
                blocks[idx].setdefault('input_json', '')
                blocks[idx]['input_json'] += delta.get('partial_json', '')
            elif delta_type == 'thinking_delta':
                blocks[idx].setdefault('thinking', '')
                blocks[idx]['thinking'] += delta.get('thinking', '')

        elif evt_type == 'message_delta':
            delta = data.get('delta', {})
            result['stop_reason'] = delta.get('stop_reason')
            # 合并 usage
            usage = data.get('usage')
            if usage:
                if result['usage']:
                    result['usage'].update(usage)
                else:
                    result['usage'] = usage

    # 整理 content blocks（按 index 排序）
    for idx in sorted(blocks.keys()):
        block = blocks[idx]
        if block['type'] == 'tool_use':
            # 尝试解析拼接的 JSON 字符串
            input_str = block.get('input_json', '')
            try:
                block['input'] = json.loads(input_str)
            except json.JSONDecodeError:
                block['input'] = input_str
            del block['input_json']
        result['content'].append(block)

    return result


# ==================== OpenAI SSE 拼接 ====================

def _assemble_openai_sse(events: list[dict]) -> dict:
    """
    拼接 OpenAI SSE 流为完整响应。
    处理 choices[].delta.content / tool_calls 等。
    """
    result = {
        'type': 'openai_sse',
        'model': None,
        'finish_reason': None,
        'usage': None,
        'content': '',
        'tool_calls': [],
    }

    # 按 index 收集 tool_calls
    tool_calls_map = {}  # index -> {id, type, function: {name, arguments}}

    for evt in events:
        data = evt.get('data', {})
        if not isinstance(data, dict):
            continue

        if not result['model'] and 'model' in data:
            result['model'] = data['model']

        if 'usage' in data and data['usage']:
            result['usage'] = data['usage']

        choices = data.get('choices', [])
        for choice in choices:
            delta = choice.get('delta', {})
            finish = choice.get('finish_reason')
            if finish:
                result['finish_reason'] = finish

            # 文本内容
            if 'content' in delta and delta['content']:
                result['content'] += delta['content']

            # 推理内容 (reasoning_content)
            if 'reasoning_content' in delta and delta['reasoning_content']:
                result.setdefault('reasoning_content', '')
                result['reasoning_content'] += delta['reasoning_content']

            # 工具调用
            if 'tool_calls' in delta:
                for tc in delta['tool_calls']:
                    tc_idx = tc.get('index', 0)
                    if tc_idx not in tool_calls_map:
                        tool_calls_map[tc_idx] = {
                            'id': tc.get('id', ''),
                            'type': tc.get('type', 'function'),
                            'function': {'name': '', 'arguments': ''},
                        }
                    entry = tool_calls_map[tc_idx]
                    if tc.get('id'):
                        entry['id'] = tc['id']
                    func = tc.get('function', {})
                    if func.get('name'):
                        entry['function']['name'] = func['name']
                    if func.get('arguments'):
                        entry['function']['arguments'] += func['arguments']

    # 整理 tool_calls
    for idx in sorted(tool_calls_map.keys()):
        tc = tool_calls_map[idx]
        # 尝试解析 arguments JSON
        try:
            tc['function']['arguments'] = json.loads(tc['function']['arguments'])
        except json.JSONDecodeError:
            pass
        result['tool_calls'].append(tc)

    if not result['tool_calls']:
        del result['tool_calls']

    return result


# ==================== 主流程 ====================

def parse_log_entry(entry: dict) -> dict:
    """解析单条日志条目为结构化数据"""
    lines = entry['lines']
    meta, body_start = parse_metadata(lines)
    req_raw, resp_raw = split_request_response(lines, body_start)

    # 确定 endpoint 路径（用于判断 SSE 格式）
    endpoint_path = meta.get('path', '')

    record = {
        'timestamp': entry['timestamp'],
        **meta,
        'request': parse_request_body(req_raw),
        'response': parse_sse_response(resp_raw, endpoint_path),
    }

    return record


def parse_log_file(filepath: str) -> list[dict]:
    """解析整个日志文件"""
    entries = split_log_entries(filepath)
    results = []
    for i, entry in enumerate(entries):
        try:
            record = parse_log_entry(entry)
            record['index'] = i
            results.append(record)
        except Exception as e:
            results.append({
                'index': i,
                'timestamp': entry.get('timestamp', ''),
                'error': f'解析失败: {str(e)}',
            })
    return results


def main():
    parser = argparse.ArgumentParser(description='解析 llm_proxy 请求日志')
    parser.add_argument('logfile', help='日志文件路径')
    parser.add_argument('-o', '--output', help='输出 JSON 文件路径（默认输出到 stdout）')
    parser.add_argument('--pretty', action='store_true', default=True, help='格式化 JSON 输出')
    parser.add_argument('--summary', action='store_true', help='只输出摘要信息')
    args = parser.parse_args()

    records = parse_log_file(args.logfile)

    if args.summary:
        # 摘要模式：只输出关键信息
        summary = []
        for r in records:
            s = {
                'index': r.get('index'),
                'timestamp': r.get('timestamp'),
                'model': r.get('model'),
                'path': r.get('path'),
                'status_code': r.get('status_code'),
                'duration_ms': r.get('duration_ms'),
                'first_byte_ms': r.get('first_byte_ms'),
            }
            resp = r.get('response', {})
            resp_type = resp.get('type', '')
            s['response_type'] = resp_type

            # 提取响应文本摘要
            if resp_type == 'anthropic_sse':
                texts = [b['text'] for b in resp.get('content', []) if b.get('type') == 'text']
                s['response_text_preview'] = _truncate(''.join(texts), 200)
                s['stop_reason'] = resp.get('stop_reason')
                tool_names = [b['name'] for b in resp.get('content', []) if b.get('type') == 'tool_use']
                if tool_names:
                    s['tool_calls'] = tool_names
            elif resp_type == 'openai_sse':
                s['response_text_preview'] = _truncate(resp.get('content', ''), 200)
                s['finish_reason'] = resp.get('finish_reason')
                tool_names = [tc['function']['name'] for tc in resp.get('tool_calls', [])]
                if tool_names:
                    s['tool_calls'] = tool_names

            summary.append(s)
        output_data = summary
    else:
        output_data = records

    indent = 2 if args.pretty else None
    json_str = json.dumps(output_data, ensure_ascii=False, indent=indent)

    if args.output:
        with open(args.output, 'w', encoding='utf-8') as f:
            f.write(json_str)
        print(f'已输出 {len(records)} 条记录到 {args.output}')
    else:
        print(json_str)


if __name__ == '__main__':
    main()
