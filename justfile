# Template testing justfile

test:
    rm -rf tmp/test-project
    uvx --with jinja2-time copier copy --defaults --trust . tmp/test-project
    ls -la tmp/test-project/

test-interactive:
    rm -rf tmp/test-project2
    uvx --with jinja2-time copier copy --trust . tmp/test-project2
