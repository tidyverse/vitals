from inspect_ai import Task, task
from inspect_ai.dataset import MemoryDataset, Sample
from inspect_ai.scorer import model_graded_qa
from inspect_ai.solver import generate, use_tools
from inspect_ai.tool import tool

@tool
def python_plot():
    async def execute(code: str):
        """Execute Python code for data analysis and plotting.
        
        Args:
            code: Python code to execute
            
        Returns:
            Output from code execution and plot as base64 image
        """
        import matplotlib
        matplotlib.use('Agg')  # Use non-interactive backend
        import matplotlib.pyplot as plt
        import numpy as np
        import pandas as pd
        import io
        import sys
        import base64
        from contextlib import redirect_stdout
        
        # Capture text output
        output_buffer = io.StringIO()
        
        try:
            # Create a namespace with common libraries
            namespace = {
                'plt': plt,
                'np': np, 
                'pd': pd,
                'matplotlib': matplotlib,
                'numpy': np,
                'pandas': pd
            }
            
            with redirect_stdout(output_buffer):
                exec(code, namespace)
            
            text_output = output_buffer.getvalue()
            
            # Check if any plots were created
            if plt.get_fignums():
                # Save plot to base64
                img_buffer = io.BytesIO()
                plt.savefig(img_buffer, format='png', bbox_inches='tight', dpi=150)
                img_buffer.seek(0)
                img_base64 = base64.b64encode(img_buffer.getvalue()).decode()
                plt.close('all')
                
                result = text_output + "\n" if text_output else ""
                result += f"Plot created: data:image/png;base64,{img_base64}"
                return result
            else:
                return text_output if text_output else "Code executed successfully (no plot created)"
            
        except Exception as e:
            return f"Error: {str(e)}"
        finally:
            plt.close('all')
    
    return execute

@task
def python_plotting_eval():
    return Task(
        dataset=MemoryDataset([
            Sample(
                input="Create a scatter plot showing the relationship between two variables. Use numpy to generate sample data with x from 0 to 10 and y = 2*x + noise, then plot it.",
                target="Should create a scatter plot using matplotlib with plt.scatter() or similar, showing a linear relationship with some noise"
            )
        ]),
        solver=[use_tools([python_plot()]), generate()],
        scorer=model_graded_qa()
    )
