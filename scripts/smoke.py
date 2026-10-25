import base64, json, os, pathlib, subprocess, tempfile
backend = pathlib.Path(__file__).resolve().parents[1] / 'Vendor/core/bin/harbor-core'
with tempfile.TemporaryDirectory(prefix='codex-harbor-test-') as directory:
    root = pathlib.Path(directory)
    (root / 'home').mkdir()
    env = dict(os.environ, CODEX_HOME=str(root / 'home'), HOME=str(root))
    def run(*args, structured=False):
        result = subprocess.run([str(backend), *args], env=env, capture_output=True, timeout=30)
        assert result.returncode == 0, 'Backend command failed: ' + args[0] + result.stderr.decode() + result.stdout.decode()
        return json.loads(result.stdout) if structured else None
    assert run('list', '--skip-api', '--json', structured=True)['accounts'] == []
    for i in range(2):
        path = root / f'fixture-{i}.json'
        payload = {'email': f'test{i}@example.invalid', 'https://api.openai.com/auth': {'chatgpt_account_id': f'account-{i}', 'chatgpt_user_id': f'user-{i}', 'chatgpt_plan_type': 'plus'}}
        token = 'e30.' + base64.urlsafe_b64encode(json.dumps(payload).encode()).decode().rstrip('=') + '.test'
        path.write_text(json.dumps({'tokens': {'id_token': token, 'access_token': 'offline-fixture', 'account_id': f'account-{i}'}}))
        run('import', str(path), '--alias', f'测试账号{i}')
    accounts = run('list', '--skip-api', '--json', structured=True)['accounts']
    assert len(accounts) == 2
    key = accounts[0]['account_key']
    run('alias', 'set', key, '中文别名')
    run('switch', key, '--json', '--restart-daemon', structured=True)
    result = run('list', '--skip-api', '--json', structured=True)
    assert result['active_account_key'] == key
    assert next(a for a in result['accounts'] if a['account_key'] == key)['alias'] == '中文别名'
    run('remove', key, '--json', structured=True)
    assert len(run('list', '--skip-api', '--json', structured=True)['accounts']) == 1
print('PASS: isolated empty list, import, alias, switch, active state, remove')
