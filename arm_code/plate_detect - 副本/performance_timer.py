import time
import signal
import sys
from collections import defaultdict

class PerformanceTimer:
    """性能计时器类，用于统计函数执行时间"""

    def __init__(self, enabled=True):
        """
        初始化性能计时器
        :param enabled: 是否启用计时功能
        """
        self.enabled = enabled
        self.timing_stats = defaultdict(list)
        self.signal_handler_setup = False

    def setup_signal_handler(self):
        """设置中断信号处理器，用于程序退出时打印平均耗时"""
        if not self.enabled or self.signal_handler_setup:
            return

        signal.signal(signal.SIGINT, self.signal_handler)
        signal.signal(signal.SIGTERM, self.signal_handler)
        self.signal_handler_setup = True

    def signal_handler(self, signum, frame):
        """中断信号处理函数，打印平均耗时并退出程序"""
        self.print_average_times()
        sys.exit(0)

    def cleanup(self):
        """清理并打印统计信息"""
        if self.enabled:
            self.print_average_times()

    def record_time(self, func_name, duration):
        """记录函数执行时间"""
        if self.enabled:
            self.timing_stats[func_name].append(duration)

    def print_average_times(self):
        """打印各函数的平均执行时间"""
        if not self.enabled or not self.timing_stats:
            return

        print("\n=== 函数执行时间统计 ===")
        for func_name, times in self.timing_stats.items():
            if times:
                avg_time = sum(times) / len(times)
                total_time = sum(times)
                print(f"{func_name}: 平均耗时 {avg_time:.4f}秒 (总耗时: {total_time:.4f}秒, 执行次数: {len(times)})")
        print("======================")

    def get_timing_stats(self):
        """获取当前计时统计信息"""
        if not self.enabled:
            return {}

        stats = {}
        for func_name, times in self.timing_stats.items():
            if times:
                stats[func_name] = {
                    'avg_time': sum(times) / len(times),
                    'total_time': sum(times),
                    'count': len(times)
                }
        return stats

    def time_function(self, func_name):
        """装饰器：用于计时函数执行时间"""
        def decorator(func):
            def wrapper(*args, **kwargs):
                if not self.enabled:
                    return func(*args, **kwargs)

                start_time = time.time()
                result = func(*args, **kwargs)
                duration = time.time() - start_time
                self.record_time(func_name, duration)
                return result
            return wrapper
        return decorator

    def clear_stats(self):
        """清除所有计时统计"""
        self.timing_stats.clear()