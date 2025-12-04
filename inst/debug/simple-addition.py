from inspect_ai import Task, task
from inspect_ai.dataset import Sample
from inspect_ai.scorer import model_graded_qa
from inspect_ai.solver import generate


@task
def simple_addition():
    dataset = [
        Sample(input="What's 2+2?", target="4"),
        Sample(input="What's 2+3?", target="5"),
        Sample(input="What's 2+4?", target="6"),
    ]

    return Task(
        dataset=dataset,
        solver=generate(),
        scorer=model_graded_qa(),
        model="anthropic/claude-sonnet-4-20250514",
    )
