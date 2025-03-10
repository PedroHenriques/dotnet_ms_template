using System.Dynamic;
using MongoDB.Driver;
using StackExchange.Redis;
using Confluent.Kafka;

WebApplicationBuilder builder = WebApplication.CreateBuilder(args);

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

WebApplication app = builder.Build();

if (app.Environment.IsDevelopment())
{
  app.UseSwagger();
  app.UseSwaggerUI();
}

app.MapGet(
  "/",
  async () =>
  {
    dynamic document = new ExpandoObject();
    document.prop1 = "value 1";
    document.prop2 = "value 2";

    string? mongoConStr = Environment.GetEnvironmentVariable("MONGO_CON_STR");
    if (mongoConStr == null)
    {
      throw new Exception("Could not get the 'MONGO_CON_STR' environment variable");
    }
    MongoClient? mongoClient = new MongoClient(mongoConStr);
    if (mongoClient == null)
    {
      throw new Exception("Mongo Client returned NULL.");
    }
    await mongoClient.GetDatabase("myTestDb").GetCollection<dynamic>("myTestCol").InsertOneAsync(document);


    string? redisConStr = Environment.GetEnvironmentVariable("REDIS_CON_STR");
    if (redisConStr == null)
    {
      throw new Exception("Could not get the 'REDIS_CON_STR' environment variable");
    }
    ConfigurationOptions redisConOpts = new ConfigurationOptions
    {
      EndPoints = { redisConStr },
    };
    IConnectionMultiplexer? redisClient = ConnectionMultiplexer.Connect(redisConOpts);
    if (redisClient == null)
    {
      throw new Exception("Redis Client returned NULL.");
    }
    var redisDb = redisClient.GetDatabase(0);
    await redisDb.StringSetAsync("prop1", document.prop1);
    await redisDb.StringSetAsync("prop2", document.prop2);


    string? kafkaConStr = Environment.GetEnvironmentVariable("KAFKA_CON_STR");
    if (kafkaConStr == null)
    {
      throw new Exception("Could not get the 'KAFKA_CON_STR' environment variable");
    }
    var config = new ProducerConfig
    {
      BootstrapServers = kafkaConStr,
    };
    var producer = new ProducerBuilder<string, string>(config).Build();
    await producer.ProduceAsync(
      "myTestTopic",
      new Message<string, string> { Key = "prop1", Value = document.prop1 }
    );
    await producer.ProduceAsync(
      "myTestTopic",
      new Message<string, string> { Key = "prop2", Value = document.prop2 }
    );


    return Results.Ok("Hello World!");
  }
);

app.Run();
