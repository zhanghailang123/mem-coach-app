import 'package:flutter/material.dart';

class McpManagementPage extends StatefulWidget {
  const McpManagementPage({super.key});

  @override
  State<McpManagementPage> createState() => _McpManagementPageState();
}

class _McpManagementPageState extends State<McpManagementPage> {
  // 模拟的 MCP Server 列表
  final List<Map<String, dynamic>> _mcpServers = [
    {
      'id': '1',
      'name': 'Local Python Tools',
      'url': 'http://localhost:8000/mcp',
      'status': 'connected',
      'toolsCount': 5,
    },
    {
      'id': '2',
      'name': 'GitHub Search MCP',
      'url': 'https://api.example.com/github-mcp',
      'status': 'disconnected',
      'toolsCount': 0,
    }
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MCP 服务管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showAddServerDialog,
            tooltip: '添加 MCP Server',
          ),
        ],
      ),
      body: _mcpServers.isEmpty
          ? const Center(
              child: Text('暂无配置的 MCP Server'),
            )
          : ListView.builder(
              itemCount: _mcpServers.length,
              itemBuilder: (context, index) {
                final server = _mcpServers[index];
                final isConnected = server['status'] == 'connected';

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isConnected ? Colors.green.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                      child: Icon(
                        Icons.hub,
                        color: isConnected ? Colors.green : Colors.grey,
                      ),
                    ),
                    title: Text(server['name']),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(server['url'], style: const TextStyle(fontSize: 12)),
                        const SizedBox(height: 4),
                        Text(
                          isConnected ? '已连接 • ${server['toolsCount']} 个工具' : '未连接',
                          style: TextStyle(
                            fontSize: 12,
                            color: isConnected ? Colors.green : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'delete') {
                          setState(() {
                            _mcpServers.removeAt(index);
                          });
                        } else if (value == 'refresh') {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('正在刷新 ${server['name']}...')),
                          );
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'refresh',
                          child: Text('刷新连接'),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('删除', style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                    isThreeLine: true,
                  ),
                );
              },
            ),
    );
  }

  void _showAddServerDialog() {
    final nameController = TextEditingController();
    final urlController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加 MCP Server'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: '服务名称',
                hintText: '例如: Local Python Tools',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: urlController,
              decoration: const InputDecoration(
                labelText: '服务地址 (URL)',
                hintText: '例如: http://localhost:8000/mcp',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (nameController.text.isNotEmpty && urlController.text.isNotEmpty) {
                setState(() {
                  _mcpServers.add({
                    'id': DateTime.now().millisecondsSinceEpoch.toString(),
                    'name': nameController.text,
                    'url': urlController.text,
                    'status': 'disconnected',
                    'toolsCount': 0,
                  });
                });
                Navigator.pop(context);
              }
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }
}
