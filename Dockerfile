FROM mcr.microsoft.com/dotnet/sdk:7.0 AS build
WORKDIR /src
COPY MictcoWebService/MictcoWebService.csproj MictcoWebService/
RUN dotnet restore MictcoWebService/MictcoWebService.csproj
COPY MictcoWebService/ MictcoWebService/
RUN dotnet publish MictcoWebService/MictcoWebService.csproj -c Release -o /app --no-restore /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:7.0
WORKDIR /app
COPY --from=build /app .
ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080
ENTRYPOINT ["dotnet", "MictcoWebService.dll"]
