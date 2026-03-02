class User:
    def __init__(self, name, email):
        self.name = name
        self.email = email

    def authenticate(self, password):
        return True
