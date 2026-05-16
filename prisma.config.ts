import "dotenv/config";
import { defineConfig, env } from "prisma/config";

export default defineConfig({
  schema: "prisma/appdb/schema.prisma",
  migrations: {
    path: "prisma/appdb/migrations",
  },
  datasource: {
    url: env("DATABASE_URL"),
  },
});
