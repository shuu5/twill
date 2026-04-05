from typing import Dict, Set

from twl.core.graph import print_tree


def print_rich_tree(graph: Dict, node_id: str):
    """Rich表示"""
    try:
        from rich.console import Console
        from rich.tree import Tree
        from rich.panel import Panel
    except ImportError:
        print("Rich not installed. Falling back to ASCII tree.")
        print("Install with: pip install rich")
        print()
        print_tree(graph, node_id)
        return

    console = Console()

    node = graph.get(node_id)
    if not node:
        console.print(f"[red]Node not found: {node_id}[/red]")
        return

    def add_children(tree: Tree, nid: str, visited: Set[str]):
        n = graph.get(nid)
        if not n or nid in visited:
            return
        visited.add(nid)

        for (t, name, *_rest) in n['calls']:
            child_id = f"{t}:{name}"
            style = "blue" if t == 'command' else "green"
            label = f"[{style}]{name}[/{style}] ({t})"
            branch = tree.add(label)
            add_children(branch, child_id, visited)

        for agent in n['uses_agents']:
            child_id = f"agent:{agent}"
            child = graph.get(child_id)
            conditional = f" [{child['conditional']}]" if child and child.get('conditional') else ""
            tree.add(f"[yellow]{agent}[/yellow] (agent){conditional}")

        for ext in n['external']:
            tree.add(f"[dim]{ext}[/dim] (external)")

    root_label = f"[bold]{node['name']}[/bold] ({node['type']})"
    tree = Tree(root_label)
    add_children(tree, node_id, set())

    console.print(Panel(tree, title="Dependency Tree"))
