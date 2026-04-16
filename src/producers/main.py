import asyncio
import signal

from producers.binance_trades import run_binance_trades
from producers.config import load_settings
from producers.kraken_depth import run_kraken_depth
from producers.redpanda import RedpandaSink


async def run() -> None:
    settings = load_settings()
    sink = RedpandaSink(bootstrap_servers=settings.redpanda_brokers)
    stop = asyncio.Event()

    loop = asyncio.get_running_loop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, stop.set)

    tasks = [
        asyncio.create_task(run_binance_trades(settings=settings, sink=sink)),
        asyncio.create_task(run_kraken_depth(settings=settings, sink=sink)),
    ]
    wait_task = asyncio.create_task(stop.wait())

    done, pending = await asyncio.wait(tasks + [wait_task], return_when=asyncio.FIRST_COMPLETED)
    if wait_task in done:
        for task in tasks:
            task.cancel()
    else:
        for task in done:
            if task.exception():
                print(f"producer task failed: {task.exception()}")
        stop.set()
        for task in tasks:
            task.cancel()

    await asyncio.gather(*tasks, return_exceptions=True)
    sink.flush()
    sink.close()


if __name__ == "__main__":
    asyncio.run(run())
