from inspect_ai.hooks import Hooks, SampleEnd, SampleEvent, hooks


def register(on_progress):
    @hooks(name="vitals_progress", description="Report eval progress to vitals.")
    class VitalsProgress(Hooks):
        async def on_sample_end(self, data: SampleEnd) -> None:
            on_progress("sample")

        async def on_sample_event(self, data: SampleEvent) -> None:
            on_progress("event")

    return VitalsProgress
