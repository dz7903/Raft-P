test tcSingleClient [main = TestWithSingleClient]:
    union { Server }, { Client }, { TestWithSingleClient };

test tcMultipleClient [main = TestWithMultipleClient]:
    union { Server }, { Client }, { TestWithMultipleClient };