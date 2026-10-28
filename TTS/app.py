import sys
import os
import re
import asyncio
import hashlib
import json
import logging
import tempfile
from dataclasses import dataclass, field
from datetime import datetime
from PyQt5.QtWidgets import (
    QApplication,
    QWidget,
    QVBoxLayout,
    QTextEdit,
    QPushButton,
    QLabel,
    QComboBox,
    QHBoxLayout,
)
from PyQt5.QtCore import pyqtSlot, QThread, pyqtSignal, QSettings
import edge_tts
import subprocess
from PyQt5.QtGui import QFont

# 获取用户的桌面路径
desktop_path = os.path.join(os.path.expanduser("~"), "Desktop")
# Kept for compatibility with callers that imported the old constant. Each task
# uses a timestamped path created by ``task_paths`` instead.
OUTPUT_FILE = os.path.join(desktop_path, "sai_tts.mp3")

DEFAULT_VOICE = {
    "晓晓": "zh-CN-XiaoxiaoNeural",
    "云夏": "zh-CN-YunxiaNeural",
    "云健": "zh-CN-YunjianNeural",
    "云扬": "zh-CN-YunyangNeural",
    "晓伊": "zh-CN-XiaoyiNeural",
    "云希": "zh-CN-YunxiNeural",
    "AndrewMultilingual": "en-US-AndrewMultilingualNeural",
    "AvaMultilingual": "en-US-AvaMultilingualNeural",
    "BrianMultilingual": "en-US-BrianMultilingualNeural",
    "EmmaMultilingual": "en-US-EmmaMultilingualNeural",
    "Emma": "en-US-EmmaNeural",
    "Jenny": "en-US-JennyNeural",
    "Michelle": "en-US-MichelleNeural",
    "Steffan": "en-US-SteffanNeural",
}

MAX_SEGMENT_LENGTH = 500  # 设置每个文本段的最大长度
SEGMENT_TIMEOUT_SECONDS = 60
ROUND_RETRY_DELAYS = (5, 15)

# Surge 的代理端口 8234， Clash Verge 的代理端口 7897
EDGE_TTS_PROXY = "http://127.0.0.1:7897"

SETTINGS_ORGANIZATION = "Sai"
SETTINGS_APPLICATION = "TTS UI"


@dataclass
class TTSTaskState:
    raw_text: str
    processed_text: str
    voice: str
    segments: list
    output_path: str
    cache_dir: str
    fingerprint: str
    completed_indexes: set = field(default_factory=set)
    rounds_completed: int = 0

    @property
    def total(self):
        return len(self.segments)

    def remaining_indexes(self):
        return [
            index
            for index in range(1, self.total + 1)
            if index not in self.completed_indexes
        ]


def split_text(text, max_length=MAX_SEGMENT_LENGTH):
    """
    按标点符号分段，并限制每段的最大字符数
    """
    sentences = re.split(r"(。|！|\!|\.|？|\?)", text)  # 按标点符号分割
    segments = []
    current_segment = ""
    for sentence in sentences:
        if not sentence.strip():
            continue
        if current_segment and len(current_segment) + len(sentence) > max_length:
            segments.append(current_segment.strip())
            current_segment = ""
        # A long sentence is split into bounded pieces instead of creating an
        # empty cache entry. Punctuation remains attached to its preceding text
        # whenever possible.
        while len(sentence) > max_length:
            if current_segment:
                room = max_length - len(current_segment)
                if room:
                    current_segment += sentence[:room]
                    sentence = sentence[room:]
                segments.append(current_segment.strip())
                current_segment = ""
            else:
                segments.append(sentence[:max_length].strip())
                sentence = sentence[max_length:]
        current_segment += sentence
    if current_segment.strip():
        segments.append(current_segment.strip())
    return segments

async def _stream_segment(segment, voice):
    communicate = edge_tts.Communicate(
        segment,
        voice,
        proxy=EDGE_TTS_PROXY or None,
    )
    segment_audio = bytearray()
    async for chunk in communicate.stream():
        if chunk["type"] == "audio":
            segment_audio.extend(chunk["data"])
    if not segment_audio:
        raise RuntimeError("No audio data received")
    return bytes(segment_audio)


async def process_segment(
    segment,
    voice,
    timeout=None,
    logger=None,
):
    """Attempt one segment once; task-level rounds provide the retries."""
    timeout = SEGMENT_TIMEOUT_SECONDS if timeout is None else timeout
    try:
        return await asyncio.wait_for(
            _stream_segment(segment, voice), timeout=float(timeout)
        )
    except Exception as exc:
        message = f"segment failed: {segment[:40]!r}: {exc}"
        if logger:
            logger.warning(message)
        else:
            print(message)
        return None


def atomic_write_bytes(path, data):
    """Write a file fully, then replace the destination in one atomic step."""
    directory = os.path.dirname(path) or "."
    os.makedirs(directory, exist_ok=True)
    fd, temporary_path = tempfile.mkstemp(prefix=".tmp-", dir=directory)
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_path, path)
    finally:
        if os.path.exists(temporary_path):
            os.unlink(temporary_path)


def atomic_write_json(path, value):
    atomic_write_bytes(path, json.dumps(value, ensure_ascii=False, indent=2).encode("utf-8"))


def task_paths():
    filename = datetime.now().strftime("sai_tts_%m%d_%H%M.mp3")
    stem = os.path.splitext(filename)[0]
    output_path = os.path.join(desktop_path, filename)
    cache_dir = os.path.join(desktop_path, stem)
    if not os.path.exists(output_path) and not os.path.exists(cache_dir):
        return output_path, cache_dir

    # A new app session never resumes an old directory. Preserve a same-minute
    # task by allocating a suffix instead of overwriting or reusing it.
    counter = 2
    while True:
        candidate_stem = f"{stem}_{counter}"
        candidate_output = os.path.join(desktop_path, f"{candidate_stem}.mp3")
        candidate_cache = os.path.join(desktop_path, candidate_stem)
        if not os.path.exists(candidate_output) and not os.path.exists(candidate_cache):
            return candidate_output, candidate_cache
        counter += 1

def preprocess_text(text):
    """
    对文本进行预处理，去掉自然段内的空格，并保留段与段之间的空格。
    """
    # 先对比值和数字的格式进行处理
    text = re.sub(r"([0-9]+)[︰:：]([0-9]+)", r"\1比\2", text)
    text = re.sub(
        r"[（(]([0-9]+)\+([0-9]+)[）)][︰:：]([0-9]+)",
        lambda m: f"{m.group(1)}加{m.group(2)}比{m.group(3)}",
        text,
    )
    text = re.sub(r"(?<!\d)(0|[1-9])\.(\d+)(?=\s|︰|:|：|$)", r"\1点\2", text)

    # 分段处理
    paragraphs = text.split("\n")  # 按段落分割
    processed_paragraphs = []
    for paragraph in paragraphs:
        if paragraph.strip():  # 非空段落
            # 处理中文之间的空格
            paragraph = re.sub(r"(?<=[\u4e00-\u9fff])\s+(?=[\u4e00-\u9fff])", "", paragraph)
            # 确保中英文之间有空格
            paragraph = re.sub(r"(?<=[\u4e00-\u9fff])\s*(?=[a-zA-Z])", " ", paragraph)
            paragraph = re.sub(r"(?<=[a-zA-Z])\s*(?=[\u4e00-\u9fff])", " ", paragraph)
            # 保留英文单词之间的空格（避免破坏正常的空格）
            paragraph = re.sub(r"(?<=[a-zA-Z])\s+(?=[a-zA-Z])", " ", paragraph)
            processed_paragraphs.append(paragraph.strip())
        else:  # 空行保留
            processed_paragraphs.append("")
        # print(processed_paragraphs)

    # 将段落重新组合，保留段间空行
    return "\n".join(processed_paragraphs)


def create_tts_task(text, voice):
    processed_text = preprocess_text(text)
    segments = split_text(processed_text)
    output_path, cache_dir = task_paths()
    os.makedirs(cache_dir, exist_ok=True)
    fingerprint = hashlib.sha256(
        json.dumps(
            {"text": processed_text, "voice": voice, "segments": segments},
            ensure_ascii=False,
        ).encode("utf-8")
    ).hexdigest()
    return TTSTaskState(
        raw_text=text,
        processed_text=processed_text,
        voice=voice,
        segments=segments,
        output_path=output_path,
        cache_dir=cache_dir,
        fingerprint=fingerprint,
    )


def persist_task_state(task_state, status, error=None):
    metadata = {
        "output": task_state.output_path,
        "voice": task_state.voice,
        "fingerprint": task_state.fingerprint,
        "segments": task_state.segments,
        "status": status,
        "rounds_completed": task_state.rounds_completed,
        "completed": sorted(task_state.completed_indexes),
        "remaining": task_state.remaining_indexes(),
    }
    if error:
        metadata["error"] = str(error)
    atomic_write_json(os.path.join(task_state.cache_dir, "metadata.json"), metadata)


def persist_failures(task_state, remaining_indexes, round_number):
    failures = [
        {
            "index": index,
            "round": round_number,
            "text": task_state.segments[index - 1],
        }
        for index in remaining_indexes
    ]
    atomic_write_json(os.path.join(task_state.cache_dir, "failures.json"), failures)


def refresh_failure_manifest(task_state):
    failures = []
    for index in task_state.remaining_indexes():
        failed_path = os.path.join(
            task_state.cache_dir, f"segment_{index:04d}.failed.json"
        )
        if os.path.isfile(failed_path):
            try:
                with open(failed_path, "r", encoding="utf-8") as handle:
                    failures.append(json.load(handle))
            except (OSError, ValueError):
                failures.append({"index": index, "text": task_state.segments[index - 1]})
    manifest_path = os.path.join(task_state.cache_dir, "failures.json")
    if failures:
        atomic_write_json(manifest_path, failures)
    elif os.path.exists(manifest_path):
        os.unlink(manifest_path)


def task_result(task_state, status, rounds_run, message):
    return {
        "status": status,
        "rounds_run": rounds_run,
        "rounds_completed": task_state.rounds_completed,
        "completed": len(task_state.completed_indexes),
        "remaining": len(task_state.remaining_indexes()),
        "total": task_state.total,
        "output_path": task_state.output_path,
        "message": message,
    }


async def run_tts(task_state, progress_callback=None):
    """Run at most three sequential passes over the task's missing segments."""
    progress_callback = progress_callback or (lambda progress: None)
    os.makedirs(task_state.cache_dir, exist_ok=True)
    logger = logging.getLogger(f"tts.{os.path.basename(task_state.cache_dir)}")
    logger.setLevel(logging.INFO)
    logger.propagate = False
    handler = logging.FileHandler(
        os.path.join(task_state.cache_dir, "task.log"), encoding="utf-8"
    )
    handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
    logger.addHandler(handler)
    rounds_run = 0
    try:
        persist_task_state(task_state, "running")
        session_round = 0
        while True:
            pending = task_state.remaining_indexes()
            if not pending:
                break
            session_round += 1
            rounds_run += 1
            absolute_round = task_state.rounds_completed + 1
            logger.info(
                "Starting round %d with %d pending segments",
                absolute_round,
                len(pending),
            )
            for position, index in enumerate(pending, start=1):
                progress_callback(
                    {
                        "phase": "processing",
                        "round": absolute_round,
                        "position": position,
                        "round_total": len(pending),
                        "completed": len(task_state.completed_indexes),
                        "total": task_state.total,
                    }
                )
                segment = task_state.segments[index - 1]
                logger.info(
                    "Generating segment %d/%d in round %d",
                    index,
                    task_state.total,
                    absolute_round,
                )
                segment_audio = await process_segment(
                    segment, task_state.voice, logger=logger
                )
                segment_path = os.path.join(
                    task_state.cache_dir, f"segment_{index:04d}.mp3"
                )
                failed_path = os.path.join(
                    task_state.cache_dir, f"segment_{index:04d}.failed.json"
                )
                if segment_audio:
                    atomic_write_bytes(segment_path, segment_audio)
                    task_state.completed_indexes.add(index)
                    if os.path.exists(failed_path):
                        os.unlink(failed_path)
                else:
                    failure = {
                        "index": index,
                        "round": absolute_round,
                        "text": segment,
                    }
                    atomic_write_json(failed_path, failure)
                    logger.error("Segment %d failed in round %d", index, absolute_round)

            task_state.rounds_completed += 1
            remaining = task_state.remaining_indexes()
            persist_task_state(task_state, "running" if remaining else "completed")
            if remaining:
                persist_failures(task_state, remaining, task_state.rounds_completed)
            logger.info(
                "Finished round %d: %d/%d complete, %d remaining",
                task_state.rounds_completed,
                len(task_state.completed_indexes),
                task_state.total,
                len(remaining),
            )
            if remaining:
                delay = ROUND_RETRY_DELAYS[
                    min(session_round - 1, len(ROUND_RETRY_DELAYS) - 1)
                ]
                progress_callback(
                    {
                        "phase": "waiting",
                        "round": task_state.rounds_completed,
                        "delay": delay,
                        "completed": len(task_state.completed_indexes),
                        "total": task_state.total,
                    }
                )
                await asyncio.sleep(delay)

        remaining = task_state.remaining_indexes()
        combined_audio = bytearray()
        for index in range(1, task_state.total + 1):
            segment_path = os.path.join(
                task_state.cache_dir, f"segment_{index:04d}.mp3"
            )
            with open(segment_path, "rb") as handle:
                combined_audio.extend(handle.read())
        if not combined_audio:
            raise RuntimeError("No audio data generated")
        atomic_write_bytes(task_state.output_path, bytes(combined_audio))
        persist_task_state(task_state, "completed")
        failure_manifest = os.path.join(task_state.cache_dir, "failures.json")
        if os.path.exists(failure_manifest):
            os.unlink(failure_manifest)
        logger.info("Audio saved atomically to %s", task_state.output_path)
        play_completion_sound()
        return task_result(
            task_state,
            "completed",
            rounds_run,
            f"语音文件生成完毕：{os.path.basename(task_state.output_path)}",
        )
    except asyncio.CancelledError:
        remaining = task_state.remaining_indexes()
        persist_task_state(task_state, "cancelled")
        refresh_failure_manifest(task_state)
        logger.info(
            "Task cancelled: %d/%d complete",
            len(task_state.completed_indexes),
            task_state.total,
        )
        message = (
            f"已取消；共 {task_state.total} 段，已完成 "
            f"{len(task_state.completed_indexes)} 段，剩余 {len(remaining)} 段"
        )
        return task_result(task_state, "cancelled", rounds_run, message)
    except Exception as exc:
        try:
            persist_task_state(task_state, "error", exc)
        except Exception:
            logger.exception("Unable to write error metadata")
        logger.exception("TTS task failed")
        return task_result(task_state, "error", rounds_run, f"出现意外错误：{exc}")
    finally:
        handler.close()
        logger.removeHandler(handler)


def play_completion_sound():
    try:
        subprocess.Popen(
            ["afplay", "/System/Library/Sounds/Glass.aiff"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except OSError:
        pass


class TTSWorker(QThread):
    result_ready = pyqtSignal(object)
    progress = pyqtSignal(object)

    def __init__(self, task_state):
        super().__init__()
        self.task_state = task_state
        self._loop = None
        self._async_task = None
        self._cancel_requested = False

    def cancel(self):
        self._cancel_requested = True
        if self._loop and self._async_task:
            self._loop.call_soon_threadsafe(self._async_task.cancel)

    def run(self):
        loop = asyncio.new_event_loop()
        self._loop = loop
        asyncio.set_event_loop(loop)
        result = None
        try:
            self._async_task = loop.create_task(
                run_tts(self.task_state, self.progress.emit)
            )
            if self._cancel_requested:
                self._async_task.cancel()
            result = loop.run_until_complete(self._async_task)
        except asyncio.CancelledError:
            remaining = len(self.task_state.remaining_indexes())
            result = task_result(
                self.task_state,
                "cancelled",
                0,
                f"已取消；共 {self.task_state.total} 段，已完成 "
                f"{len(self.task_state.completed_indexes)} 段，剩余 {remaining} 段",
            )
        except Exception as exc:
            result = task_result(
                self.task_state, "error", 0, f"出现意外错误：{exc}"
            )
        finally:
            pending = asyncio.all_tasks(loop)
            for task in pending:
                task.cancel()
            if pending:
                loop.run_until_complete(asyncio.gather(*pending, return_exceptions=True))
            loop.close()
            self._async_task = None
            self._loop = None
        self.result_ready.emit(result)


class TTSApp(QWidget):
    def __init__(self):
        super().__init__()
        self.current_task = None
        self.tts_thread = None
        self.settings = QSettings(SETTINGS_ORGANIZATION, SETTINGS_APPLICATION)
        self.setWindowTitle("文字转语音工具")
        self.setGeometry(300, 300, 1000, 800)
        self.setupUI()

    def setupUI(self):
        # 正确创建 QVBoxLayout 实例
        self.layout = QVBoxLayout(self)  #

        # 设置整体字体
        font = QFont("Arial", 14)
        self.setFont(font)

        # 创建界面元素
        self.text_input = QTextEdit()
        self.text_input.setPlaceholderText("请输入文字...")
        self.layout.addWidget(self.text_input)

        self.voice_dropdown = QComboBox()
        self.voice_dropdown.addItems(list(DEFAULT_VOICE.keys()))
        saved_voice = self.settings.value("voice_name", "")
        if saved_voice in DEFAULT_VOICE:
            self.voice_dropdown.setCurrentText(saved_voice)
        self.voice_dropdown.currentTextChanged.connect(self.save_voice_preference)
        self.layout.addWidget(self.voice_dropdown)

        self.button_layout = QHBoxLayout()
        self.layout.addLayout(self.button_layout)

        # 设置按钮样式
        button_style = """
            QPushButton {
                background-color: #4CAF50;
                border: none;
                color: white;
                padding: 10px 20px;
                text-align: center;
                text-decoration: none;
                font-size: 16px;
                margin: 4px 2px;
                border-radius: 10px;
            }
            QPushButton:hover {
                background-color: #45a049;
            }
            QPushButton:disabled {
                background-color: #ccc;
                color: #666;
            }
        """
        # 生成按钮（左侧）
        self.generate_button = QPushButton("生成")
        self.generate_button.setStyleSheet(button_style)
        self.generate_button.clicked.connect(self.start_tts)
        self.button_layout.addWidget(self.generate_button)

        # 取消按钮（右侧）
        self.cancel_button = QPushButton("取消")
        self.cancel_button.setStyleSheet(button_style)
        self.cancel_button.clicked.connect(self.cancel_tts)
        self.cancel_button.setDisabled(True)
        self.button_layout.addWidget(self.cancel_button)

        # # 创建状态标签并添加到布局中
        self.status_label = QLabel("")
        self.layout.addWidget(self.status_label)

    @pyqtSlot(str)
    def save_voice_preference(self, voice_name):
        if voice_name in DEFAULT_VOICE:
            self.settings.setValue("voice_name", voice_name)
            self.settings.sync()


    @pyqtSlot()
    def start_tts(self):
        if self.tts_thread and self.tts_thread.isRunning():
            return
        if self.current_task is None:
            text = self.text_input.toPlainText()
            if not text.strip():
                self.status_label.setText("请输入一些文本！")
                return
            selected_voice_name = self.voice_dropdown.currentText()
            voice_id = DEFAULT_VOICE.get(selected_voice_name)
            self.current_task = create_tts_task(text, voice_id)
            if not self.current_task.segments:
                self.current_task = None
                self.status_label.setText("请输入一些文本！")
                return
            self.text_input.setDisabled(True)
            self.voice_dropdown.setDisabled(True)

        self.generate_button.setDisabled(True)
        self.cancel_button.setDisabled(False)
        self.status_label.setText(
            f"准备处理剩余 {len(self.current_task.remaining_indexes())} 个片段..."
        )
        self.tts_thread = TTSWorker(self.current_task)
        self.tts_thread.result_ready.connect(self.tts_finished)
        self.tts_thread.progress.connect(self.update_progress)
        self.tts_thread.start()

    @pyqtSlot()
    def cancel_tts(self):
        if self.tts_thread and self.tts_thread.isRunning():
            self.cancel_button.setDisabled(True)
            self.status_label.setText("正在取消，请稍候...")
            self.tts_thread.cancel()

    @pyqtSlot(object)
    def update_progress(self, progress):
        if progress["phase"] == "waiting":
            self.status_label.setText(
                f"第 {progress['round']} 轮完成，已完成 "
                f"{progress['completed']}/{progress['total']}；"
                f"{progress['delay']} 秒后继续下一轮"
            )
            return
        self.status_label.setText(
            f"第 {progress['round']} 轮：正在处理本轮 "
            f"{progress['position']}/{progress['round_total']}；"
            f"总计已完成 {progress['completed']}/{progress['total']}"
        )

    @pyqtSlot(object)
    def tts_finished(self, result):
        self.cancel_button.setDisabled(True)
        self.generate_button.setDisabled(False)
        self.status_label.setText(result["message"])
        if result["status"] == "completed":
            self.current_task = None
            self.generate_button.setText("生成")
            self.text_input.setDisabled(False)
            self.voice_dropdown.setDisabled(False)
        else:
            self.generate_button.setText("继续处理剩余片段")

    def closeEvent(self, event):
        if self.tts_thread and self.tts_thread.isRunning():
            self.tts_thread.cancel()
            self.tts_thread.wait()
        event.accept()

# 主函数
if __name__ == "__main__":
    app = QApplication(sys.argv)
    ex = TTSApp()
    ex.show()
    sys.exit(app.exec_())
