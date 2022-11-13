def engine(name, path):
    native.new_local_repository(
        name = name,
        path = path,
        build_file_content = """exports_files(glob(["**"]))""",
    )
